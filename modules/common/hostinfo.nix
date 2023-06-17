{ pkgs, lib, config, ... }:

let
  cfg = config.custom.hostinfo;
in
{
  options.custom.hostinfo = {
    enable = lib.mkEnableOption "hostinfo";
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;

      virtualHosts.":30653".extraConfig = ''
        respond /nixos/system/configurationRevision ${config.system.configurationRevision} 200
        respond 404
      '';
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 30653 ];
  };
}
