{ pkgs, lib, config, ... }:

let
  cfg = config.custom.services.acme_dns_api;
  dnsCfg = config.custom.services.authoritative_dns;
  domain = config.ogygia.domain;
  knotc = "${pkgs.knot-dns}/bin/knotc";

  # Extract IP from first Knot listen address (format: "IP@port")
  knotListenAddr = builtins.head (lib.strings.splitString "@"
    (builtins.head config.services.knot.settings.server.listen));
in
{
  options.custom.services.acme_dns_api = {
    enable = lib.mkEnableOption "acme_dns_api";
  };

  config = lib.mkIf cfg.enable {
    # Requires authoritative DNS to be enabled on the same host
    assertions = [{
      assertion = dnsCfg.enable;
      message = "acme_dns_api requires authoritative_dns to be enabled";
    }];

    systemd.services.acme-dns-api = {
      description = "ACME DNS-01 Challenge API";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "knot.service" ];

      script = "${pkgs.writers.writePerl "acme-dns-api" {
        libraries = with pkgs.perlPackages; [
          HTTPDaemon
          JSON
          NetDNS
        ];
      } ''
        use v5.10;
        use warnings;
        use strict;

        use HTTP::Daemon;
        use HTTP::Status;
        use JSON qw(decode_json encode_json);
        use Net::DNS;
        use Socket qw(inet_ntoa);
        use POSIX qw(strftime);

        # Disable output buffering
        $| = 1;

        sub log_msg {
            my ($msg) = @_;
            my $ts = strftime("%Y-%m-%d %H:%M:%S", localtime);
            print "[$ts] $msg\n";
        }

        my $DOMAIN = "${domain}";
        my $PORT = 8553;
        my $LISTEN_ADDR = "${config.custom.dns.nebula.ipv4}";
        my $KNOTC = "${knotc}";

        # DNS resolver for validation - query local authoritative Knot
        my $resolver = Net::DNS::Resolver->new(
            nameservers => ['${knotListenAddr}'],
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

            # Validate that the FQDN is within our domain
            unless ($fqdn =~ /\.\Q$DOMAIN\E\.?$/) {
                log_msg("Rejected: FQDN $fqdn is not within $DOMAIN");
                return (RC_FORBIDDEN, "FQDN $fqdn is not within $DOMAIN");
            }

            # Validate client IP matches DNS resolution
            log_msg("Validating client IP $client_ip for $fqdn");
            my ($valid, $msg) = validate_client($client_ip, $fqdn);
            unless ($valid) {
                log_msg("Rejected: $msg");
                return (RC_FORBIDDEN, $msg);
            }
            log_msg("Client validation passed");

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

        # Create daemon listening on Nebula interface
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
      ''}";

      serviceConfig = {
        User = "knot";
        Group = "knot";
        Restart = "always";
        RestartSec = "5s";

        # Security hardening
        NoNewPrivileges = true;
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

  };
}
