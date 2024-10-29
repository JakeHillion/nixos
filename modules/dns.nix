{ pkgs, lib, config, ... }:

let
  cfg = config.custom.dns;
in
{
  options.custom.dns = {
    enable = lib.mkEnableOption "dns";

    authoritative = {
      ipv4 = lib.mkOption {
        description = "authoritative ipv4 mappings";
        readOnly = true;
      };
      ipv6 = lib.mkOption {
        description = "authoritative ipv6 mappings";
        readOnly = true;
      };
    };

    tailscale =
      {
        ipv4 = lib.mkOption {
          description = "tailscale ipv4 address";
          readOnly = true;
        };
        ipv6 = lib.mkOption {
          description = "tailscale ipv6 address";
          readOnly = true;
        };
      };
  };

  config = lib.mkIf cfg.enable {
    custom.dns.authoritative = {
      ipv4 = {
        uk = {
          co = {
            hillion = {
              ts = {
                cx = {
                  boron = "100.113.188.46";
                };
                home = {
                  microserver = "100.105.131.47";
                  router = "100.105.71.48";
                };
                jakehillion-terminals = { gendry = "100.70.100.77"; };
                lt = { be = "100.105.166.79"; };
                pop = {
                  li = "100.106.87.35";
                  sodium = "100.87.188.4";
                };
                st = {
                  phoenix = "100.92.37.106";
                };
                storage = {
                  theon = "100.104.142.22";
                };
              };
            };
          };
        };
      };
      ipv6 = {
        uk = {
          co = {
            hillion = {
              ts = {
                cx = {
                  boron = "fd7a:115c:a1e0::2a01:bc2f";
                };
                home = {
                  microserver = "fd7a:115c:a1e0:ab12:4843:cd96:6269:832f";
                  router = "fd7a:115c:a1e0:ab12:4843:cd96:6269:4730";
                };
                jakehillion-terminals = { gendry = "fd7a:115c:a1e0:ab12:4843:cd96:6246:644d"; };
                lt = { be = "fd7a:115c:a1e0::9001:a64f"; };
                pop = {
                  li = "fd7a:115c:a1e0::e701:5723";
                  sodium = "fd7a:115c:a1e0::3701:bc04";
                };
                st = {
                  phoenix = "fd7a:115c:a1e0::6901:256a";
                };
                storage = {
                  theon = "fd7a:115c:a1e0::4aa8:8e16";
                };
              };
            };
          };
        };
      };
    };

    custom.dns.tailscale =
      let
        lookupFqdn = lib.attrsets.attrByPath (lib.reverseList (lib.splitString "." config.networking.fqdn)) null;
      in
      {
        ipv4 = lookupFqdn cfg.authoritative.ipv4;
        ipv6 = lookupFqdn cfg.authoritative.ipv6;
      };

    networking.hosts =
      let
        mkHosts = hosts:
          (lib.collect (x: (builtins.hasAttr "name" x && builtins.hasAttr "value" x))
            (lib.mapAttrsRecursive
              (path: value:
                lib.nameValuePair value [ (lib.concatStringsSep "." (lib.reverseList path)) ])
              hosts));
      in
      builtins.listToAttrs (mkHosts cfg.authoritative.ipv4 ++ mkHosts cfg.authoritative.ipv6);
  };
}
