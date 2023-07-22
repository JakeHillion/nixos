{ config, pkgs, lib, ... }:

let
  cfg = config.custom;
  lazyUsers = { };
in
{
  options.custom = {
    users = lib.mkOption {
      description = "Create a user with the correct group and a consistent uid.";
      type = with lib.types; listOf str;
      default = [ ];
    };
    groups = lib.mkOption {
      description = "Create a group with a consistent gid.";
      type = with lib.types; listOf str;
      default = [ ];
    };
  };

  config = {
    ids.uids = {
      ## Defined System Users (see https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/misc/ids.nix)

      ## Consistent People
      jake = 1000;
      joseph = 1001;
    };
    ids.gids = {
      ## Defined System Groups (see https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/misc/ids.nix)

      ## Consistent Groups
      mediaaccess = 1200;
    };

    users.groups = builtins.listToAttrs (builtins.map
      (g: {
        name = g;
        value = {
          gid = config.ids.gids.${u};
        };
      })
      cfg.groups);
    users.users = builtins.listToAttrs (builtins.map
      (u: {
        name = u;
        value = {
          uid = config.ids.gids.${u};
        } // (if builtins.hasAttr u lazyUsers then lazyUsers.${u} else { group = "users"; });
      })
      cfg.users);
  };
}
