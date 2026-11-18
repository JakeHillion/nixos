{ config, lib, ... }:

{
  imports = [
    ./l2tp.nix
    ./host.nix
    ./registry.nix
    ./router.nix
  ];

  options.custom.network.self = lib.mkOption {
    readOnly = true;
    description = "This host's record in the device registry.";
  };

  config.custom.network.self =
    config.custom.network.devices.${lib.strings.removeSuffix ".${config.ogygia.domain}" config.networking.fqdn};
}
