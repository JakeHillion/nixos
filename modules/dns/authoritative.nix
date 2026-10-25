{ lib, ... }:

# The fleet's authoritative name-to-address map. It depends on nothing NixOS
# provides, so castaways evaluate it too: the Nebula topology is derived from
# its `neb` subtree.

{
  options.custom.dns.authoritative = {
    ipv4 = lib.mkOption {
      description = "authoritative ipv4 mappings";
      readOnly = true;
    };
    ipv6 = lib.mkOption {
      description = "authoritative ipv6 mappings";
      readOnly = true;
    };
  };

  config.custom.dns.authoritative = {
    ipv4 = {
      me = {
        jakehillion = {
          neb = {
            cx = {
              boron = "172.20.0.1";
              fanboy = "172.20.0.26";
              fritz = "172.20.0.29";
              iceman = "172.20.0.27";
              maverick = "172.20.0.25";
              rooster = "172.20.0.16";
              warlock = "172.20.0.15";
            };
            gw = {
              cyclone = "172.20.0.18";
            };
            home = {
              microserver = "172.20.0.2"; # removed 23/12/2024
              router = "172.20.0.3";
            };
            io = {
              wolfman = "172.20.0.28";
            };
            jakehillion-terminals = {
              gendry = "172.20.0.4"; # removed 18/04/2025
            };
            lt = {
              be = "172.20.0.5";
              bob = "172.20.0.24";
              jakehillion-mba-m2-15 = "172.20.0.6";
              jakehillion-mba-m5-15 = "172.20.0.30";
              macvm = "172.20.0.22";
            };
            mob = {
              jakes-ipad = "172.20.0.17";
              jakes-iphone = "172.20.0.13";
            };
            pop = {
              # hangman = "172.20.0.23"; # removed 01/06/2026
              li = "172.20.0.7";
              slider = "172.20.0.21";
              sodium = "172.20.0.8"; # removed 18/04/2025
              stinger = "172.20.0.9";
              viper = "172.20.0.20";
            };
            rig = {
              merlin = "172.20.0.10";
            };
            st = {
              phoenix = "172.20.0.11";
              sundown = "172.20.0.19";
            };
            storage = {
              theon = "172.20.0.12";
            };
            tick = {
              iceman = "172.20.0.14"; # removed 06/07/2025
            };
          };
          home = {
            iot = {
              slzb-06mu = "10.239.19.15";
              stinger = "10.239.19.8";
            };
          };
        };
      };
    };

    ipv6 = { };
  };
}
