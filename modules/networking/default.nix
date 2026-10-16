{ ... }:

{
  imports = [
    ./l2tp.nix
    ./router.nix
    ./wan_failover.nix
    ./topology.nix
  ];
}
