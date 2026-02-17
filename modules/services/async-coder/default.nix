{ config, lib, ... }:

let
  cfg = config.custom.services.async_coder;
  fqdnParts = lib.splitString "." config.networking.fqdn;
  shortHost = "${builtins.elemAt fqdnParts 0}.${builtins.elemAt fqdnParts 1}";
in
{
  options.custom.services.async_coder = {
    enable = lib.mkEnableOption "async-coder";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."async-coder/${shortHost}.password" = {
      file = ./${shortHost}.password.age;
      owner = "async-coder";
      group = "async-coder";
    };

    users.users.async-coder.uid = config.ids.uids.async-coder;
    users.groups.async-coder.gid = config.ids.gids.async-coder;

    services.async-coder = {
      enable = true;
      settings = {
        homeserver_url = "https://matrix.hillion.co.uk";
        username = shortHost;
        password_file = config.age.secrets."async-coder/${shortHost}.password".path;

        store_path = "/var/lib/async-coder/store";
        device_display_name = "async-coder";
        trusted_users = [ "@jake:hillion.co.uk" ];
        root_space = "!WhggIMMfLMutJEDsdv:hillion.co.uk";

        forges.gitea = {
          type = "gitea";
          url = "https://gitea.hillion.co.uk";
          repositories = [
            { owner = "JakeHillion"; name = "async-coder"; }
          ];
        };
      };
    };
  };
}
