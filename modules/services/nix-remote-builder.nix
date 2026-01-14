{ config, lib, ... }:

let
  cfg = config.custom.services.nix-remote-builder;

  # Look up public key from knownHosts by hostname
  getHostKey = hostname:
    config.programs.ssh.knownHosts.${hostname}.publicKey;
in
{
  options.custom.services.nix-remote-builder = {
    enable = lib.mkEnableOption "nix remote builder server";

    authorizedHosts = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Hostnames (from programs.ssh.knownHosts) authorized to connect as nix-builder";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.nix-builder = {
      isSystemUser = true;
      group = "nix-builder";
      shell = "/bin/sh";
      openssh.authorizedKeys.keys = builtins.map getHostKey cfg.authorizedHosts;
    };
    users.groups.nix-builder = { };

    nix.settings.trusted-users = [ "nix-builder" ];
  };
}
