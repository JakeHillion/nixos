{ config, pkgs, lib, ... }:

{
  config = {
    ids.uids = {
      ## Defined System Users (see https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/misc/ids.nix)
      unifi = 183;

      ## Consistent People
      jake = 1000;
      joseph = 1001;
    };
    ids.gids = {
      ## Defined System Groups (see https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/misc/ids.nix)
      unifi = 183;

      ## Consistent Groups
      mediaaccess = 1200;
    };
  };
}
