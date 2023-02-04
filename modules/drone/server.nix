{ config, pkgs, lib, ... }:

{
  config.age.secrets."drone/gitea_client_secret".file = ../../secrets/drone/gitea_client_secret.age;
  config.age.secrets."drone/rpc_secret".file = ../../secrets/drone/rpc_secret.age;

  config.virtualisation.oci-containers.containers."drone" = {
    image = "drone/drone:2.16.0";
    volumes = [ "/data/drone:/data" ];
    ports = [ "18733:80" ];
    environment = {
      DRONE_AGENTS_ENABLED = "true";
      DRONE_GITEA_SERVER = "https://gitea.hillion.co.uk";
      DRONE_GITEA_CLIENT_ID = "687ee331-ad9e-44fd-9e02-7f1c652754bb";
      DRONE_SERVER_HOST = "drone.hillion.co.uk";
      DRONE_SERVER_PROTO = "https";
      DRONE_LOGS_DEBUG = "true";
      DRONE_USER_CREATE = "username:JakeHillion,admin:true";
    };
    environmentFiles = [
      config.age.secrets."drone/gitea_client_secret".path
      config.age.secrets."drone/rpc_secret".path
    ];
  };
}
