# Snapshot of the home router's generated network configuration
{ lib, inputs, ... }:

let
  routers = lib.filterAttrs (fqdn: _: lib.hasPrefix "cyclone.gw." fqdn) inputs.self.nixosConfigurations;
  config = (lib.head (lib.attrValues routers)).config;

  unitText = units: lib.mapAttrs (_: unit: unit.text) (lib.filterAttrs (_: unit: unit.enable) units);

  # Kea matches reservations by hardware address, so their order carries no
  # meaning.
  sortReservations = subnet: subnet // {
    reservations = lib.sort (a: b: a.ip-address < b.ip-address) subnet.reservations;
  };
in
{
  nftables = {
    ruleset = config.networking.nftables.ruleset;
    tables = lib.mapAttrs (_: table: { inherit (table) family content; })
      (lib.filterAttrs (_: table: table.enable) config.networking.nftables.tables);
  };

  kea = config.services.kea.dhcp4.settings // {
    subnet4 = map sortReservations config.services.kea.dhcp4.settings.subnet4;
  };

  radvd = config.services.radvd.config;

  networkd = unitText config.systemd.network.units;
  initrdNetworkd = unitText config.boot.initrd.systemd.network.units;
}
