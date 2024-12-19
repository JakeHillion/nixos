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

    tailscale = {
      ipv4 = lib.mkOption {
        description = "tailscale ipv4 address";
        readOnly = true;
      };
      ipv6 = lib.mkOption {
        description = "tailscale ipv6 address";
        readOnly = true;
      };
    };

    nebula = {
      ipv4 = lib.mkOption {
        description = "tailscale ipv4 address";
        readOnly = true;
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [{
        assertion =
          let
            collectIps = attrset: lib.foldlAttrs
              (acc: key: item:
                if lib.isAttrs item then
                  acc ++ (collectIps item)
                else
                  acc ++ [ item ]
              ) [ ]
              attrset;
            ips = collectIps config.custom.dns.authoritative.ipv4.me.jakehillion.neb;
          in
          lib.length ips == lib.length (lib.unique ips);
        message = "duplicate nebula ip detected! nebula ips must be unique";
      }];

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
                    stinger = "100.117.89.126";
                  };
                  rig = {
                    merlin = "100.69.181.56";
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

          me = {
            jakehillion = {
              neb = {
                cx = {
                  boron = "172.20.0.1";
                };
                home = {
                  microserver = "172.20.0.2";
                  router = "172.20.0.3";
                };
                jakehillion-terminals = { gendry = "172.20.0.4"; };
                lt = {
                  be = "172.20.0.5";
                  jakehillion-mba-m2-15 = "172.20.0.6";
                };
                mob = {
                  jakes-iphone = "172.20.0.13";
                };
                pop = {
                  li = "172.20.0.7";
                  sodium = "172.20.0.8";
                  stinger = "172.20.0.9";
                };
                rig = {
                  merlin = "172.20.0.10";
                };
                st = {
                  phoenix = "172.20.0.11";
                };
                storage = {
                  theon = "172.20.0.12";
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
                    stinger = "fd7a:115c:a1e0::8401:597e";
                  };
                  rig = {
                    merlin = "fd7a:115c:a1e0::8d01:b538";
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
    }

    (lib.mkIf cfg.enable {
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
    })
  ];
}
