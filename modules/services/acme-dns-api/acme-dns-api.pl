use v5.10;
use warnings;
use strict;

use HTTP::Daemon;
use HTTP::Status;
use JSON qw(decode_json encode_json);
use Net::DNS;
use Socket qw(inet_ntoa);
use POSIX qw(strftime);
use Crypt::Ed25519;
use LWP::UserAgent;
use MIME::Base64;

# Get configuration from environment variables
my $DOMAIN = $ENV{ACME_DNS_DOMAIN} // die "ACME_DNS_DOMAIN not set\n";
my $LISTEN_ADDR = $ENV{ACME_DNS_LISTEN_ADDR} // die "ACME_DNS_LISTEN_ADDR not set\n";
my $KNOTC = $ENV{ACME_DNS_KNOTC} // die "ACME_DNS_KNOTC not set\n";
my $KNOT_NAMESERVER = $ENV{ACME_DNS_KNOT_NAMESERVER} // die "ACME_DNS_KNOT_NAMESERVER not set\n";
my $PORT = 8553;
my $KEYSERVER_PORT = 80;
my $NONCE_TTL = 300;

# Disable output buffering
$| = 1;

sub log_msg {
    my ($msg) = @_;
    my $ts = strftime("%Y-%m-%d %H:%M:%S", localtime);
    print "[$ts] $msg\n";
}

# DNS resolver for validation - query local authoritative Knot
my $resolver = Net::DNS::Resolver->new(
    nameservers => [$KNOT_NAMESERVER],
    recurse => 0,
);

my $ua = LWP::UserAgent->new(timeout => 10, ssl_opts => { verify_hostname => 0 });
my %nonce_store = ();

sub get_client_ip {
    my ($conn) = @_;
    my $peer = $conn->peerhost();
    return $peer;
}

sub resolve_fqdn_to_ip {
    my ($fqdn) = @_;

    # Remove trailing dot if present
    $fqdn =~ s/\.$//;

    # Query for A record (follows CNAMEs automatically)
    my $query = $resolver->query($fqdn, 'A');
    if ($query) {
        foreach my $rr ($query->answer) {
            if ($rr->type eq 'A') {
                return $rr->address;
            }
        }
    }
    return undef;
}

sub validate_client {
    my ($client_ip, $fqdn) = @_;

    # Strip _acme-challenge. prefix
    my $host_fqdn = $fqdn;
    $host_fqdn =~ s/^_acme-challenge\.//;
    $host_fqdn =~ s/\.$//;

    # Resolve the hostname
    my $resolved_ip = resolve_fqdn_to_ip($host_fqdn);
    unless (defined $resolved_ip) {
        return (0, "Failed to resolve $host_fqdn");
    }

    # Compare IPs
    if ($client_ip eq $resolved_ip) {
        return (1, "OK");
    } else {
        return (0, "Client IP $client_ip does not match resolved IP $resolved_ip for $host_fqdn");
    }
}

sub fetch_public_key {
    my ($client_ip) = @_;
    my $url = "http://$client_ip:$KEYSERVER_PORT/.well-known/acme-dns-key";
    log_msg("Fetching public key from $url");

    my $response = $ua->get($url);
    unless ($response->is_success) {
        log_msg("Failed to fetch public key: " . $response->status_line);
        return undef;
    }

    my $pubkey = $response->decoded_content;
    unless ($pubkey && length($pubkey) == 32) {
        log_msg("Invalid public key length: " . length($pubkey));
        return undef;
    }
    return $pubkey;
}

sub generate_nonce {
    my @chars = ('a'..'z', 'A'..'Z', '0'..'9');
    my $nonce = "";
    $nonce .= $chars[rand @chars] for 1..32;
    return $nonce;
}

sub store_nonce {
    my ($nonce, $client_ip) = @_;
    $nonce_store{$nonce} = { client_ip => $client_ip, created => time() };
}

sub validate_and_consume_nonce {
    my ($nonce, $client_ip) = @_;
    my $now = time();

    for my $key (keys %nonce_store) {
        delete $nonce_store{$key} if ($now - $nonce_store{$key}->{created} > $NONCE_TTL);
    }

    return (0, "Invalid or expired nonce") unless exists $nonce_store{$nonce};
    return (0, "Nonce issued to different client") unless $nonce_store{$nonce}->{client_ip} eq $client_ip;

    delete $nonce_store{$nonce};
    return (1, "OK");
}

sub verify_signature {
    my ($client_ip, $fqdn, $value, $nonce, $sig_b64) = @_;

    my $pubkey = fetch_public_key($client_ip);
    return (0, "Failed to fetch public key") unless $pubkey;

    my $sig = decode_base64($sig_b64);
    return (0, "Invalid signature format") unless ($sig && length($sig) == 64);

    my $payload = encode_json({ fqdn => $fqdn, value => $value, nonce => $nonce });

    if (Crypt::Ed25519::verify($pubkey, $payload, $sig)) {
        return (1, "Signature verified");
    } else {
        return (0, "Signature verification failed");
    }
}

sub add_txt_record {
    my ($fqdn, $value) = @_;

    # Remove trailing dot and domain suffix to get relative name
    $fqdn =~ s/\.$//;
    $fqdn =~ s/\.\Q$DOMAIN\E$//;

    log_msg("Adding TXT record: $fqdn = $value");

    # Use knotc for atomic zone transaction
    log_msg("Running: knotc zone-begin $DOMAIN");
    system($KNOTC, "zone-begin", $DOMAIN) == 0
        or do { log_msg("zone-begin failed"); return (0, "zone-begin failed"); };

    log_msg("Running: knotc zone-set $DOMAIN $fqdn 60 TXT \"$value\"");
    my $ret = system($KNOTC, "zone-set", $DOMAIN, $fqdn, "60", "TXT", "\"$value\"");
    if ($ret != 0) {
        log_msg("zone-set failed (exit code $ret), aborting");
        system($KNOTC, "zone-abort", $DOMAIN);
        return (0, "zone-set failed");
    }

    log_msg("Running: knotc zone-commit $DOMAIN");
    system($KNOTC, "zone-commit", $DOMAIN) == 0
        or do { log_msg("zone-commit failed"); return (0, "zone-commit failed"); };

    log_msg("TXT record added successfully");
    return (1, "Record added");
}

sub remove_txt_record {
    my ($fqdn, $value) = @_;

    # Remove trailing dot and domain suffix to get relative name
    $fqdn =~ s/\.$//;
    $fqdn =~ s/\.\Q$DOMAIN\E$//;

    log_msg("Removing TXT record: $fqdn");

    # Use knotc for atomic zone transaction
    log_msg("Running: knotc zone-begin $DOMAIN");
    system($KNOTC, "zone-begin", $DOMAIN) == 0
        or do { log_msg("zone-begin failed"); return (0, "zone-begin failed"); };

    log_msg("Running: knotc zone-unset $DOMAIN $fqdn TXT");
    my $ret = system($KNOTC, "zone-unset", $DOMAIN, $fqdn, "TXT");
    if ($ret != 0) {
        log_msg("zone-unset failed (exit code $ret), aborting");
        system($KNOTC, "zone-abort", $DOMAIN);
        return (0, "zone-unset failed");
    }

    log_msg("Running: knotc zone-commit $DOMAIN");
    system($KNOTC, "zone-commit", $DOMAIN) == 0
        or do { log_msg("zone-commit failed"); return (0, "zone-commit failed"); };

    log_msg("TXT record removed successfully");
    return (1, "Record removed");
}

sub handle_request {
    my ($conn, $req) = @_;

    my $method = $req->method;
    my $path = $req->uri->path;
    my $client_ip = get_client_ip($conn);

    log_msg("Request: $method $path from $client_ip");

    # Handle nonce endpoint (GET allowed)
    if ($path eq '/nonce') {
        my $nonce = generate_nonce();
        store_nonce($nonce, $client_ip);
        log_msg("Generated nonce for $client_ip: $nonce");
        return (RC_OK, encode_json({ nonce => $nonce }));
    }

    # Only allow POST for /present and /cleanup
    unless ($method eq 'POST') {
        log_msg("Rejected: method not allowed");
        return (RC_METHOD_NOT_ALLOWED, "Method not allowed");
    }

    # Parse JSON body
    my $body = $req->content;
    my $data;
    eval {
        $data = decode_json($body);
    };
    if ($@) {
        log_msg("Rejected: invalid JSON - $@");
        return (RC_BAD_REQUEST, "Invalid JSON: $@");
    }

    my $fqdn = $data->{fqdn};
    my $value = $data->{value};
    my $nonce = $data->{nonce};
    my $signature = $data->{signature};

    log_msg("Parsed request: fqdn=$fqdn value=$value");

    unless (defined $fqdn && defined $value && defined $nonce && defined $signature) {
        log_msg("Rejected: missing fqdn, value, nonce, or signature");
        return (RC_BAD_REQUEST, "Missing fqdn, value, nonce, or signature");
    }

    # Validate that the FQDN is within our domain
    unless ($fqdn =~ /\.\Q$DOMAIN\E\.?$/) {
        log_msg("Rejected: FQDN $fqdn is not within $DOMAIN");
        return (RC_FORBIDDEN, "FQDN $fqdn is not within $DOMAIN");
    }

    # Validate and consume nonce
    log_msg("Validating nonce for $client_ip");
    my ($nonce_ok, $nonce_msg) = validate_and_consume_nonce($nonce, $client_ip);
    unless ($nonce_ok) {
        log_msg("Rejected: $nonce_msg");
        return (RC_FORBIDDEN, $nonce_msg);
    }
    log_msg("Nonce validation passed");

    # Verify signature
    log_msg("Verifying signature from $client_ip");
    my ($sig_ok, $sig_msg) = verify_signature($client_ip, $fqdn, $value, $nonce, $signature);
    unless ($sig_ok) {
        log_msg("Rejected: $sig_msg");
        return (RC_FORBIDDEN, $sig_msg);
    }
    log_msg("Signature verification passed");

    if ($path eq '/present') {
        my ($ok, $result) = add_txt_record($fqdn, $value);
        if ($ok) {
            log_msg("Response: 200 OK - $result");
            return (RC_OK, encode_json({status => "ok", message => $result}));
        } else {
            log_msg("Response: 500 Error - $result");
            return (RC_INTERNAL_SERVER_ERROR, $result);
        }
    } elsif ($path eq '/cleanup') {
        my ($ok, $result) = remove_txt_record($fqdn, $value);
        if ($ok) {
            log_msg("Response: 200 OK - $result");
            return (RC_OK, encode_json({status => "ok", message => $result}));
        } else {
            log_msg("Response: 500 Error - $result");
            return (RC_INTERNAL_SERVER_ERROR, $result);
        }
    } else {
        log_msg("Rejected: unknown endpoint $path");
        return (RC_NOT_FOUND, "Unknown endpoint");
    }
}

# Create daemon listening on specified interface
my $d = HTTP::Daemon->new(
    LocalAddr => $LISTEN_ADDR,
    LocalPort => $PORT,
    ReuseAddr => 1,
) || die "Failed to create HTTP daemon: $!";

log_msg("ACME DNS API listening on $LISTEN_ADDR:$PORT");

while (my $conn = $d->accept) {
    while (my $req = $conn->get_request) {
        my ($status, $response) = handle_request($conn, $req);

        my $http_response = HTTP::Response->new($status);
        $http_response->header('Content-Type' => 'application/json');
        $http_response->content($response);
        $conn->send_response($http_response);
    }
    $conn->close;
    undef($conn);
}
