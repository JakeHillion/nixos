# Builds the `ogygiaConfigurations` entry for the castaway defined in
# `castaways/<fqdn>`. See modules/castaway for what a castaway is.
{ ogygia, lib }:

fqdn:
ogygia.lib.mkOgygiaConfiguration {
  name = fqdn;
  inherit lib;
  modules = [
    ../modules/castaway
    ../castaways/${fqdn}
  ];
}
