{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.switches;
  inherit (config.custom.network) networks devices ports;

  switches = lib.attrsets.filterAttrs (_: device: device.kind != null) devices;

  vlan = network: networks.${network}.vlan;
  vlans = memberships: lib.lists.sort lib.trivial.lessThan (map vlan memberships);

  # A port cabled to a registered device carries that device's networks. Any
  # other port says what it carries itself.
  port = switch: number: entry:
    if entry.device == null then {
      inherit (entry) description;
      native = lib.trivial.mapNullable vlan entry.native;
      tagged = if entry.tagged == "all" then "all" else vlans entry.tagged;
    }
    else
      let
        nets = devices.${entry.device}.net;
        untagged = lib.attrsets.attrNames (lib.attrsets.filterAttrs (_: membership: !membership.tagged) nets);
      in
      {
        description = entry.device;
        native =
          if untagged == [ ] then null
          else if lib.lists.length untagged == 1 then vlan (lib.lists.head untagged)
          else throw "network/ports/${switch}.toml: ${entry.device} on port ${number} has more than one untagged network";
        tagged = vlans (lib.attrsets.attrNames (lib.attrsets.filterAttrs (_: membership: membership.tagged) nets));
      };

  # How each kind of switch is reached, and the script that configures it
  kinds = {
    edgeswitch = {
      script = pkgs.writers.writePython3 "activate-edgeswitch"
        { flakeIgnore = [ "E203" "W503" ]; }
        (builtins.readFile ./edgeswitch.py);
      path = [ pkgs.iputils pkgs.openssh pkgs.sshpass ];
      # For pinging the gateway
      capabilities = [ "CAP_NET_RAW" ];
      # Each EdgeSwitch has its own admin password
      secret = name: {
        name = "switches/${name}";
        rekeyFile = ./. + "/${name}.agent.age";
      };
      state = name: switch:
        let
          # The switch is managed over the network it has an address on
          management = lib.lists.head (lib.attrsets.attrNames
            (lib.attrsets.filterAttrs (_: membership: membership.ipv4 != null) switch.net));
        in
        {
          address = switch.net.${management}.ipv4;
          gateway = networks.${management}.gateway;
          user = "admin";
          vlans = lib.attrsets.mapAttrs' (netName: network: lib.attrsets.nameValuePair (toString network.vlan) netName) networks;
        };
    };

    unifi = {
      script = pkgs.writers.writePython3 "activate-unifi"
        { flakeIgnore = [ "E203" "W503" ]; }
        (builtins.readFile ./unifi.py);
      path = [ ];
      capabilities = [ ];
      # UniFi switches are all configured through the one controller
      secret = _: {
        name = "switches/unifi";
        rekeyFile = ./unifi.age;
      };
      state = _: switch: {
        controller = "https://unifi.hillion.co.uk";
        site = "Home";
        user = "nix-admin";
        inherit (switch) mac;
      };
    };
  };
in
{
  options.custom.services.switches = {
    enable = lib.mkEnableOption "applying the network registry to the managed switches";

    state = lib.mkOption {
      readOnly = true;
      internal = true;
      description = "The desired state of each managed switch, as handed to the script that applies it.";
    };
  };

  config = lib.mkMerge [
    {
      custom.services.switches.state = lib.attrsets.mapAttrs
        (name: switch: kinds.${switch.kind}.state name switch // {
          ports = lib.attrsets.mapAttrs (port name) ports.${name};
        })
        switches;
    }

    (lib.mkIf cfg.enable {
      age.secrets = lib.attrsets.mapAttrs'
        (name: switch:
          let secret = kinds.${switch.kind}.secret name; in
          lib.attrsets.nameValuePair secret.name { inherit (secret) rekeyFile; })
        switches;

      # Each switch's unit changes with its desired state, so a deploy restarts
      # exactly the units of the switches whose configuration changed.
      systemd.services = lib.attrsets.mapAttrs'
        (name: switch:
          let kind = kinds.${switch.kind}; in
          lib.attrsets.nameValuePair "activate-switch-${name}" {
            description = "Apply the network registry to ${name}";
            wantedBy = [ "multi-user.target" ];
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];

            inherit (kind) path;

            serviceConfig = {
              Type = "oneshot";
              # A deploy only restarts a changed unit that is still active
              RemainAfterExit = true;
              DynamicUser = true;
              AmbientCapabilities = kind.capabilities;
              LoadCredential = "password:${config.age.secrets.${(kind.secret name).name}.path}";
              ExecStart = "${kind.script} --password-file %d/password ${(pkgs.formats.json { }).generate "switch-${name}.json" cfg.state.${name}}";
            };
          })
        switches;
    })
  ];
}
