{ config, pkgs, lib, ... }:

let
  cfg = config.custom.storj;
in
{
  options.custom.storj = {
    enable = lib.mkEnableOption "storj";

    instances = lib.mkOption {
      type = with lib.types; attrsOf
        (submodule {
          options = {
            configDir = lib.mkOption {
              type = str;
            };
            identityDir = lib.mkOption {
              type = str;
            };
            storage = lib.mkOption {
              type = str;
            };
            consoleAddress = lib.mkOption {
              type = str;
              default = "127.0.0.1:14002";
            };
            serverPort = lib.mkOption {
              type = port;
              default = 28967;
            };
            externalAddress = lib.mkOption {
              type = nullOr str;
              default = null;
            };
            authorizationTokenFile = lib.mkOption {
              type = nullOr str;
              default = null;
            };
          };
        });
      default = { };
    };

    wallet = lib.mkOption {
      type = lib.types.str;
    };
    email = lib.mkOption {
      type = lib.types.str;
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.storj = { };
    users.users.storj = {
      isSystemUser = true;
      createHome = false;
      group = "storj";
    };

    systemd.services =
      let
        mkService = name: value: {
          name = "storj-${name}";
          value = {
            description = "Storj storagenode ${name}";
            wantedBy = [ "multi-user.target" ];

            script =
              let
                args = lib.concatStringsSep "\\\n  " ([
                  "--config-dir '${value.configDir}'"
                  "--identity-dir '${value.identityDir}'"
                  "--operator.email '${cfg.email}'"
                  "--operator.wallet '${cfg.wallet}'"
                  "--console.address '${value.consoleAddress}'"
                  "--server.address ':${toString value.serverPort}'"
                  "--server.private-address ':0'"
                  "--storage.allocated-disk-space '${value.storage}'"
                ] ++ (if value.externalAddress == null then [ ] else [
                  "--contact.external-address '${value.externalAddress}'"
                ]));
              in
              with pkgs;
              (if value.authorizationTokenFile == null then "" else ''
                if ! grep -c BEGIN ${value.identityDir}/ca.cert; then
                  rm -rf ${value.identityDir}/storagenode
                  ${storj}/bin/identity create storagenode \
                    --identity-dir '${value.identityDir}'
                  ${storj}/bin/identity authorize storagenode \
                    $(cat ${value.authorizationTokenFile}) \
                    --identity-dir '${value.identityDir}' \
                    --signer.tls.revocation-dburl 'bolt://${value.identityDir}/revocations.db'
                  mv ${value.identityDir}/storagenode/* ${value.identityDir}
                  rm -d ${value.identityDir}/storagenode
                fi
              '') + ''
                if ! test -f ${value.configDir}/config.yaml; then
                  ${storj}/bin/storagenode setup ${args}
                fi
                ${storj}/bin/storagenode run ${args}
              '';

            serviceConfig = {
              User = "storj";
              Group = "storj";

              Restart = "always";
              RestartSec = 10;
            };

            unitConfig = {
              RequiresMountsFor = lib.concatStringsSep " " [ value.configDir value.identityDir ];
            };
          };
        };
      in
      builtins.listToAttrs (lib.attrsets.mapAttrsToList mkService cfg.instances);

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = lib.attrsets.mapAttrsToList (name: value: value.serverPort) cfg.instances;
      allowedUDPPorts = lib.attrsets.mapAttrsToList (name: value: value.serverPort) cfg.instances;
    };
  };
}
