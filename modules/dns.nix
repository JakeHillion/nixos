{ pkgs, lib, config, ... }:

let
  cfg = config.custom.dns;
  v4Hosts = {
    uk = {
      co = {
        hillion = {
          ts = {
            cx = {
              boron = "100.112.54.25";
              jorah = "100.96.143.138";
            };
            home = {
              microserver = "100.105.131.47";
              router = "100.105.71.48";
            };
            jakehillion-terminals = { gendry = "100.70.100.77"; };
            lt = { be = "100.105.166.79"; };
            pop = { li = "100.106.87.35"; };
            storage = {
              theon = "100.104.142.22";
              tywin = "100.115.31.91";
            };
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
            cx = {
              boron = "fd7a:115c:a1e0::2a01:3619";
              jorah = "fd7a:115c:a1e0:ab12:4843:cd96:6260:8f8a";
            };
            home = {
              microserver = "fd7a:115c:a1e0:ab12:4843:cd96:6269:832f";
              router = "fd7a:115c:a1e0:ab12:4843:cd96:6269:4730";
            };
            jakehillion-terminals = { gendry = "fd7a:115c:a1e0:ab12:4843:cd96:6246:644d"; };
            lt = { be = "fd7a:115c:a1e0::9001:a64f"; };
            pop = { li = "fd7a:115c:a1e0::e701:5723"; };
            storage = {
              theon = "fd7a:115c:a1e0::4aa8:8e16";
              tywin = "fd7a:115c:a1e0:ab12:4843:cd96:6273:1f5b";
            };
          };
        };
      };
    };
  };
in
{
  options.custom.dns = {
    enable = lib.mkEnableOption "dns";

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
    custom.dns.tailscale =
      let
        lookupFqdn = lib.attrsets.attrByPath (lib.reverseList (lib.splitString "." config.networking.fqdn)) null;
      in
      {
        ipv4 = lookupFqdn v4Hosts;
        ipv6 = lookupFqdn v6Hosts;
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
      builtins.listToAttrs (mkHosts v4Hosts ++ mkHosts v6Hosts);
  };
}
