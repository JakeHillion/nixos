{ config, lib, ... }:

let
  cfg = config.custom.services.status;
in
{
  options.custom.services.status = {
    enable = lib.mkEnableOption "status";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."dashboard/ssh.key".file = ../../secrets/dashboard/ssh.key.age;

    ogygia.dashboard = {
      enable = true;
      title = "Jake's Home Lab Status";
      serverConfig = { port = 47283; };

      ssh = {
        enable = true;
        url = "git@ssh.gitea.hillion.co.uk:JakeHillion/nixos.git";
        keyFile = config.age.secrets."dashboard/ssh.key".path;
      };

      archive.enable = true;
    };

    custom.www.nebula = {
      enable = true;
      virtualHosts."status.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy http://127.0.0.1:47283
      '';
    };
  };
}
