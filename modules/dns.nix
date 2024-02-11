{ pkgs, lib, config, ... }:

let
  cfg = config.custom.dns;
  v4Hosts = {
    uk = {
      co = {
        hillion = {
          ts = {
            strangervm = { vm = "100.110.89.111"; };
            cx = { jorah = "100.96.143.138"; };
          };
        };
      };
    };
  };
  v6Hosts = {
    uk = {
      co = {
        hillion = {
          ts = {
            strangervm = { vm = "fd7a:115c:a1e0:ab12:4843:cd96:626e:596f"; };
            cx = { jorah = "fd7a:115c:a1e0:ab12:4843:cd96:6260:8f8a"; };
          };
        };
      };
    };
  };
in
{
  options.custom.dns = {
    enable = lib.mkEnableOption "dns";
    tailscale = {
      ipv4 = "TODO: lookup ip in v4Hosts";
      ipv6 = "TODO: lookup fqdn in v6Hosts";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.hosts = { };
  };
}
