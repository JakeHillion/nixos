{ config, pkgs, lib, ... }:

{
  options.custom.oci-containers = {
    versions = lib.mkOption {
      description = "oci container versions";
      readOnly = true;
    };
  };

  config = {
    custom.oci-containers.versions = builtins.fromJSON (builtins.readFile ./versions.json);
  };
}
