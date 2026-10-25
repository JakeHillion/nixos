{ pkgs, lib, config, ... }:

let
  cfg = config.custom.dns;
in
{
  imports = [ ./authoritative.nix ];

  options.custom.dns = {
    enable = lib.mkEnableOption "dns";

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
