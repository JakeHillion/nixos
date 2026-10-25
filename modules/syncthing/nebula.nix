# The `ogygia.nebula` settings for a Syncthing peer, NixOS host or castaway:
# the cert group that lets it reach other peers' sync port, and the rule that
# lets them reach its own.
{
  groups = [ "syncthing" ];
  firewall.inbound = [
    { groups = [ "syncthing" ]; port = 22000; proto = "tcp"; }
  ];
}
