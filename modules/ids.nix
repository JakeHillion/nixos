{ config, pkgs, lib, ... }:

{
  config = {
    ids.uids = {
      ## Defined System Users (see https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/misc/ids.nix)
      unifi = 183;
      chia = 185;
      gitea = 186;
      node-exporter = 188;
      step-ca = 198;
      isponsorblocktv = 199;
      frigate = 200;
      nebula-jakehillion = 205;
      immich = 206;

      ## Consistent People
      jake = 1000;
      joseph = 1001;

      ## Extra system users
      btrbk = 2000;
    };
    ids.gids = {
      ## Defined System Groups (see https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/misc/ids.nix)
      unifi = 183;
      chia = 185;
      gitea = 186;
      node-exporter = 188;
      step-ca = 198;
      isponsorblocktv = 199;
      frigate = 200;
      nebula-jakehillion = 205;
      immich = 206;

      ## Consistent Groups
      mediaaccess = 1200;

      ## Extra system groups
      btrbk = 2000;
    };
  };
}
