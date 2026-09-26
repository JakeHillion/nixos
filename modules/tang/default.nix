{ config, pkgs, lib, ... }:

let
  cfg = config.custom.tang;

  fqdn = config.networking.fqdn;
  domain = config.ogygia.domain;

  group = lib.lists.findSingle
    (g: lib.lists.elem fqdn g.clients)
    (throw "${fqdn} enables tang but is not a client of any group in custom.tang.fleet.groups")
    (throw "${fqdn} is a client of multiple groups in custom.tang.fleet.groups")
    (lib.attrsets.attrValues cfg.fleet.groups);
in
{
  options.custom.tang = {
    enable = lib.mkEnableOption "tang";

    networkingModule = lib.mkOption {
      type = lib.types.str;
    };

    secretFile = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };

    devices = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };

    fleet = {
      servers = lib.mkOption {
        description = ''
          Tang servers by FQDN: the thumbprint of each server's signing key
          (from `tang-show-keys 7654`) and the URLs it is reachable at, keyed
          by how it is reached.
        '';
        readOnly = true;
      };

      groups = lib.mkOption {
        description = ''
          Groups of clients that bind to the same servers. `pins` maps a
          server FQDN to which of its URLs the clients use, `sources` are the
          addresses those servers see the clients connect from.
        '';
        readOnly = true;
      };
    };
  };

  config = lib.mkMerge [
    {
      custom.tang.fleet = {
        servers = {
          "cyclone.gw.${domain}" = {
            thp = "L-njyA01teJse7gxbkBJMc6DuLKrwlvqfrbvKj528m4";
            lan = "http://10.64.50.1:7654";
            wan = "http://185.240.111.53:7654";
          };
          "warlock.cx.${domain}" = {
            thp = "m4sWMYoNuEv1Z5PuWeZ3tUkfFSJCyaeL4WxYWQY6piU";
            lan = "http://10.64.50.21:7654";
          };
          "stinger.pop.${domain}" = {
            thp = "mk6z2KAxuW1zee0S7D7qOFchgyiyei9XvJaF9pJkqK0";
            lan = "http://10.64.50.29:7654";
          };
          "boron.cx.${domain}" = {
            thp = "UzoraC1HFiCmhtz6f43N-6sqY77YDHXNi7Eow9RA9D0";
            wan = "http://138.201.252.214:7654";
          };
          "li.pop.${domain}" = {
            thp = "_rbDZVBx35wwUu36P7C-DlQJhQQt4zO8g6r5prT0RWs";
            wan = "http://80.229.251.26:7654";
          };
        };

        groups = {
          # Hosts behind cyclone. They only unlock while they can reach the
          # home servers over the LAN, never from the Internet.
          home = {
            pins = {
              "cyclone.gw.${domain}" = "lan";
              "warlock.cx.${domain}" = "lan";
              "stinger.pop.${domain}" = "lan";
            };
            clients = [
              "maverick.cx.${domain}"
              "merlin.rig.${domain}"
              "phoenix.st.${domain}"
              "rooster.cx.${domain}"
              "stinger.pop.${domain}"
              "sundown.st.${domain}"
              "warlock.cx.${domain}"
              "wolfman.io.${domain}"
            ];
            sources = [ "10.64.50.0/24" ];
          };

          internet = {
            pins = {
              "cyclone.gw.${domain}" = "wan";
              "boron.cx.${domain}" = "wan";
              "li.pop.${domain}" = "wan";
            };
            clients = [
              "boron.cx.${domain}"
              "cyclone.gw.${domain}"
              "iceman.cx.${domain}"
              "slider.pop.${domain}"
              "viper.pop.${domain}"
            ];
            sources = [
              "37.27.136.99/32" # iceman
              "138.201.252.214/32" # boron
              "140.238.103.110/32" # slider
              "185.240.111.53/32" # cyclone
            ];
          };
        };
      };
    }

    (lib.mkIf cfg.enable {
      boot.initrd = {
        availableKernelModules = [ cfg.networkingModule ];

        # Configure systemd-networkd directly in initrd. We don't go via
        # boot.initrd.network.enable because that auto-translates the full
        # stage 2 networking.interfaces.* into boot.initrd.systemd.network,
        # which doesn't tolerate stage 2 route schemas (e.g. cyclone's
        # cellular VLAN).
        systemd.network = {
          enable = true;
          # Fallback DHCP on the tang interface. Hosts that set a static
          # `ip=...` kernel parameter get a higher-priority 91-*.network from
          # systemd-network-generator that wins over this 99-*.
          networks."99-tang-dhcp" = {
            matchConfig.Driver = cfg.networkingModule;
            networkConfig.DHCP = "yes";
          };
        };

        clevis = {
          enable = true;
          useTang = true;

          devices = builtins.listToAttrs (builtins.map
            (dev: {
              name = dev;
              value = { secretFile = cfg.secretFile; };
            })
            cfg.devices);
        };
      };

      ogygia.clevis = {
        enable = true;
        secretFile = cfg.secretFile;
        spec = {
          t = 1;
          pins.tang = lib.attrsets.mapAttrsToList
            (server: via: {
              url = cfg.fleet.servers.${server}.${via};
              inherit (cfg.fleet.servers.${server}) thp;
            })
            (lib.attrsets.removeAttrs group.pins [ fqdn ]);
        };
      };
    })
  ];
}
