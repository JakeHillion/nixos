{ config, pkgs, lib, ... }:

let
  cfg = config.custom.users;
in
{
  options.custom.users = {
    jake = {
      password = lib.mkOption {
        description = "Enable an interactive password.";
        type = lib.types.bool;
        default = false;
      };
    };
  };

  config = lib.mkIf cfg.jake.password {
    age.secrets."passwords/jake".file = ../secrets/passwords/jake.age;
    users.users.jake.hashedPasswordFile = config.age.secrets."passwords/jake".path;
  };
}
