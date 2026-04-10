{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "24.05";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.kernelParams = [
      "ip=dhcp"
    ];
    boot.initrd = {
      availableKernelModules = [ "igc" ];
      network.enable = true;
      clevis = {
        enable = true;
        useTang = true;
        devices = {
          "disk0-crypt".secretFile = "/data/disk_encryption.jwe";
        };
      };
    };

    # BeeLink GTi14 has stability issues on 6.12 (and probably a bit before).
    # Pin to the latest kernel for now, as the current default (LTS) is 6.12.
    boot.kernelPackages = pkgs.linuxPackages_latest;

    custom.defaults = true;
    custom.locations.autoServe = true;
    custom.profiles.devbox = true;

    custom.services.ollama.models = [
      "deepseek-coder-v2:16b"
      "qwen2.5-coder:14b"
    ];

    custom.users.jake.password = true;
    security.sudo.wheelNeedsPassword = lib.mkForce true;
    custom.desktop.sway.enable = true;

    ## Impermanence
    custom.impermanence = {
      enable = true;
      userExtraFiles.jake = [ ".ssh/id_ecdsa" ];
    };

    ## Video drivers when docked
    boot.initrd.kernelModules = [ "amdgpu" ];
    services.xserver.videoDrivers = [ "amdgpu" ];

    # Allow performing aarch64 builds in QEMU
    boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

    ## Podman
    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        dockerSocket.enable = true;
      };
    };

    ## Udisks
    services.udisks2.enable = true;

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/data/users/jake/sync";
    };

    ## Spotify
    services.pipewire.enable = lib.mkForce false;
    services.pulseaudio.enable = true;
    users.users.jake.extraGroups = [ "audio" ];

    home-manager.users.jake.services.spotifyd = {
      enable = true;
      settings = {
        global = {
          device_name = "merlin.rig";
          device_type = "computer";
          bitrate = 320;

          backend = "pulseaudio";
        };
      };
    };

    # Networking
    networking = {
      interfaces.enp171s0.name = "eth0";
      interfaces.enp172s0.name = "eth1";
    };
    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers

    networking.firewall = {
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [ ];
          allowedUDPPorts = lib.mkForce [ ];
        };
      };
    };

    # Boot control service for Windows/NixOS selection via Home Assistant
    age.secrets."merlin/homeassistant-api-token" = {
      file = ./homeassistant-api-token.age;
      owner = "root";
      group = "root";
    };

    systemd.services.boot-control = {
      description = "Boot Control Service - Check Home Assistant for Windows boot preference";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "auto_updater.service" ];
      wants = [ "network-online.target" ];
      requires = [ "auto_updater.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        User = "root";
        EnvironmentFile = config.age.secrets."merlin/homeassistant-api-token".path;
      };
      script = ''
        set -euo pipefail

        # Home Assistant API endpoint
        HASS_URL="https://homeassistant.hillion.co.uk"
        API_ENDPOINT="$HASS_URL/api/states/input_boolean.merlin_boot_windows"

        echo "Checking Home Assistant boot preference..."
        
        # Query the input_boolean state with retries
        for i in {1..5}; do
          if RESPONSE=$(${pkgs.curl}/bin/curl -s -f -H "Authorization: Bearer $HASS_API_TOKEN" "$API_ENDPOINT" 2>/dev/null); then
            break
          else
            echo "Attempt $i failed, retrying in 5 seconds..."
            sleep 5
          fi
        done

        if [ -z "''${RESPONSE:-}" ]; then
          echo "Failed to reach Home Assistant after 5 attempts, skipping boot control"
          exit 0
        fi

        # Parse the state using jq
        STATE=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.state')
        
        if [ "$STATE" = "on" ]; then
          echo "Home Assistant indicates Windows boot requested"
          
          # Set Windows as next boot option
          echo "Setting Windows as next boot target..."
          ${pkgs.systemd}/bin/bootctl set-oneshot "auto-windows"
          
          echo "Rebooting to Windows..."
          ${pkgs.systemd}/bin/systemctl reboot
        else
          echo "Home Assistant indicates NixOS boot (state: $STATE), continuing with NixOS"
        fi
      '';
    };
  };
}
