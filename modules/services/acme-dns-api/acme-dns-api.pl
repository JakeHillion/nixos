use v5.10;
use warnings;
use strict;

use HTTP::Daemon;
use HTTP::Status;
use JSON qw(decode_json encode_json);
use Net::DNS;
use Socket qw(inet_ntoa);
use POSIX qw(strftime);

# Get configuration from environment variables
my $DOMAINS_STR = $ENV{ACME_DNS_DOMAIN} // die "ACME_DNS_DOMAIN not set\n";
my $LISTEN_ADDR = $ENV{ACME_DNS_LISTEN_ADDR} // die "ACME_DNS_LISTEN_ADDR not set\n";
my $KNOTC = $ENV{ACME_DNS_KNOTC} // die "ACME_DNS_KNOTC not set\n";
my $KNOT_NAMESERVER = $ENV{ACME_DNS_KNOT_NAMESERVER} // die "ACME_DNS_KNOT_NAMESERVER not set\n";
my $PORT = 8553;

# Parse comma-separated list of domains
my @DOMAINS = sort { length($b) <=> length($a) } split(/,\s*/, $DOMAINS_STR);

# Disable output buffering
$| = 1;

sub log_msg {
    my ($msg) = @_;
    my $ts = strftime("%Y-%m-%d %H:%M:%S", localtime);
    print "[$ts] $msg\n";
}

# Find which domain a FQDN belongs to (longest match first)
sub find_domain_for_fqdn {
    my ($fqdn) = @_;
    $fqdn =~ s/\.$//;
    foreach my $domain (@DOMAINS) {
        my $dotted = $domain;
        $dotted =~ s/\.$//;
        if ($fqdn eq $dotted || $fqdn =~ /\.\Q$dotted\E$/) {
            return $dotted;
        }
    }
    return undef;
}

# DNS resolver for validation - query local authoritative Knot
my $resolver = Net::DNS::Resolver->new(
    nameservers => [$KNOT_NAMESERVER],
    recurse => 0,
);

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

sub add_txt_record {
    my ($fqdn, $value, $domain) = @_;

    # Remove trailing dot and domain suffix to get relative name
    $fqdn =~ s/\.$//;
    $fqdn =~ s/\.\Q$domain\E$//;

    log_msg("Adding TXT record: $fqdn in zone $domain = $value");

    # Use knotc for atomic zone transaction
    log_msg("Running: knotc zone-begin $domain");
    system($KNOTC, "zone-begin", $domain) == 0
        or do { log_msg("zone-begin failed"); return (0, "zone-begin failed"); };

    log_msg("Running: knotc zone-set $domain $fqdn 60 TXT \"$value\"");
    my $ret = system($KNOTC, "zone-set", $domain, $fqdn, "60", "TXT", "\"$value\"");
    if ($ret != 0) {
        log_msg("zone-set failed (exit code $ret), aborting");
        system($KNOTC, "zone-abort", $domain);
        return (0, "zone-set failed");
    }

    log_msg("Running: knotc zone-commit $domain");
    system($KNOTC, "zone-commit", $domain) == 0
        or do { log_msg("zone-commit failed"); return (0, "zone-commit failed"); };

    log_msg("TXT record added successfully");
    return (1, "Record added");
}

sub remove_txt_record {
    my ($fqdn, $value, $domain) = @_;

    # Remove trailing dot and domain suffix to get relative name
    $fqdn =~ s/\.$//;
    $fqdn =~ s/\.\Q$domain\E$//;

    log_msg("Removing TXT record: $fqdn in zone $domain");

    # Use knotc for atomic zone transaction
    log_msg("Running: knotc zone-begin $domain");
    system($KNOTC, "zone-begin", $domain) == 0
        or do { log_msg("zone-begin failed"); return (0, "zone-begin failed"); };

    log_msg("Running: knotc zone-unset $domain $fqdn TXT");
    my $ret = system($KNOTC, "zone-unset", $domain, $fqdn, "TXT");
    if ($ret != 0) {
        log_msg("zone-unset failed (exit code $ret), aborting");
        system($KNOTC, "zone-abort", $domain);
        return (0, "zone-unset failed");
    }

    log_msg("Running: knotc zone-commit $domain");
    system($KNOTC, "zone-commit", $domain) == 0
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

    # Only allow POST
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

    log_msg("Parsed request: fqdn=$fqdn value=$value");

    unless (defined $fqdn && defined $value) {
        log_msg("Rejected: missing fqdn or value");
        return (RC_BAD_REQUEST, "Missing fqdn or value");
    }

    # Find which domain this FQDN belongs to
    my $matched_domain = find_domain_for_fqdn($fqdn);
    unless (defined $matched_domain) {
        log_msg("Rejected: FQDN $fqdn is not within any managed domain");
        return (RC_FORBIDDEN, "FQDN $fqdn is not within any managed domain");
    }
    log_msg("Matched domain: $matched_domain");

    # Validate client IP matches DNS resolution
    log_msg("Validating client IP $client_ip for $fqdn");
    my ($valid, $msg) = validate_client($client_ip, $fqdn);
    unless ($valid) {
        log_msg("Rejected: $msg");
        return (RC_FORBIDDEN, $msg);
    }
    log_msg("Client validation passed");

    if ($path eq '/present') {
        my ($ok, $result) = add_txt_record($fqdn, $value, $matched_domain);
        if ($ok) {
            log_msg("Response: 200 OK - $result");
            return (RC_OK, encode_json({status => "ok", message => $result}));
        } else {
            log_msg("Response: 500 Error - $result");
            return (RC_INTERNAL_SERVER_ERROR, $result);
        }
    } elsif ($path eq '/cleanup') {
        my ($ok, $result) = remove_txt_record($fqdn, $value, $matched_domain);
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

log_msg("ACME DNS API listening on $LISTEN_ADDR:$PORT for domains: " . join(', ', @DOMAINS));

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
