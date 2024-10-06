{ config, lib, ... }:

{
  imports = [
    ./global.nix
    ./home.nix
    ./iot.nix
    ./www-repo.nix
  ];
}
