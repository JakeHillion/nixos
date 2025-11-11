{ pkgs, lib, config, ... }:

{
  options.custom.laptop = lib.mkEnableOption "laptop";
}
