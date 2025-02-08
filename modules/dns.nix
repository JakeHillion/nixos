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

    nebula = {
      ipv4 = lib.mkOption {
        description = "nebula ipv4 address";
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
          me = {
            jakehillion = {
              neb = {
                cx = {
                  boron = "172.20.0.1";
                  warlock = "172.20.0.15";
                };
                home = {
                  microserver = "172.20.0.2"; # removed 23/12/2024
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
                tick = {
                  iceman = "172.20.0.14";
                };
              };
            };
          };
        };

        ipv6 = { };
      };
    }

    (lib.mkIf cfg.enable {
      custom.dns =
        let
          lookupFqdn = fqdn: lib.attrsets.attrByPath (lib.reverseList (lib.splitString "." fqdn)) null;
          lookupConfiguredFqdn = lookupFqdn config.networking.fqdn;
        in
        {
          nebula.ipv4 = lookupConfiguredFqdn cfg.authoritative.ipv4;
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
