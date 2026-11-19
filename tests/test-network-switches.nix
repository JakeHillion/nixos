# Snapshot of the desired state rendered for each managed switch
{ lib, inputs, ... }:

let
  hosts = lib.filterAttrs (_: host: host.config.custom.services.switches.enable) inputs.self.nixosConfigurations;
in
(lib.head (lib.attrValues hosts)).config.custom.services.switches.state
