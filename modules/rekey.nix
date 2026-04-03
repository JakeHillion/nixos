{ config, lib, ... }:

let
  hostKeys = import ./ssh/host-keys.nix;
in
{
  config.age.rekey = {
    masterIdentities = [{
      identity = ../secrets/master-key.age;
      pubkey = "age1ql5y0epk7y75gn6skwtvsa6xfzqzxdhvwl4r8z2dl6x0mhrmzfjqp9zkxt";
    }];
    storageMode = "local";
    localStorageDir = ./. + "/../secrets/rekeyed/${config.networking.hostName}";
  } // lib.optionalAttrs (hostKeys.byFqdn ? ${config.networking.fqdn}) {
    hostPubkey = hostKeys.byFqdn.${config.networking.fqdn};
  };
}
