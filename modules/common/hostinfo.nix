{ pkgs, lib, config, ... }:

let
  cfg = config.custom.hostinfo;
in
{
  options.custom.hostinfo = {
    enable = lib.mkEnableOption "hostinfo";
  };

  config = lib.mkIf cfg.enable {
    systemd.services.hostinfo = {
      description = "Expose hostinfo over HTTP.";

      wantedBy = [ "multi-user.target" ];

      script = "${pkgs.writers.writePerl "hostinfo" {
        libraries = with pkgs; [
          perl536Packages.HTTPDaemon
        ];
      } ''
        use v5.10;
        use warnings;
        use strict;

        use HTTP::Daemon;
        use HTTP::Status;

        my $d = HTTP::Daemon->new(LocalPort => 30653) || die;
        while (my $c = $d->accept) {
          while (my $r = $c->get_request) {
            if ($r->method eq 'GET') {
              given ($r->uri->path) {
                when ('/current/nixos/system/configurationRevision') {
                  $c->send_file_response("/nix/var/nix/gcroots/current-system/etc/flake-version");
                }
                when ('/booted/nixos/system/configurationRevision') {
                  $c->send_file_response("/nix/var/nix/gcroots/booted-system/etc/flake-version");
                }
                default {
                  $c->send_error(404);
                }
              }
            } else {
              $c->send_error(RC_FORBIDDEN);
            }
          }
          $c->close;
          undef($c);
        }
      ''}";

      serviceConfig = {
        DynamicUser = true;
        Restart = "always";
      };
    };

    environment.etc = {
      flake-version = {
        source = builtins.toFile "flake-version" "${config.system.configurationRevision}";
        mode = "0444";
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 30653 ];
  };
}
