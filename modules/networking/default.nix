{ ... }:

{
  imports = [
    ./router.nix
    ./wan_failover.nix
    ./topology.nix
  ];
}
