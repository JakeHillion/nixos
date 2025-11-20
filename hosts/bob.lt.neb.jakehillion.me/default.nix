{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-gpd-pocket-4
  ];

  config = {
    system.stateVersion = "25.05";

    custom.defaults = true;
    custom.profiles.devbox.enable = true;
    custom.home.neomutt.backup = false;

    custom.home.opencode = {
      enable = true;
      includeLocalProvider = true;
      providers = {
        merlin = {
          name = "Merlin";
          baseURL = "http://ollama.${config.ogygia.domain}:11434/v1";
          models = {
            "qwen2.5-coder:14b" = {
              id = "ollama_chat/qwen2.5-coder:14b";
              displayName = "Qwen2.5 Coder 14B";
            };
            "deepseek-coder-v2:16b" = {
              id = "ollama_chat/deepseek-coder-v2:16b";
              displayName = "DeepSeek Coder V2 16B";
            };
          };
        };
        rooster = {
          name = "Rooster";
          baseURL = "http://ollama.${config.ogygia.domain}:11434/v1";
          models = {
            "qwen2.5-coder:14b" = {
              id = "ollama_chat/qwen2.5-coder:14b";
              displayName = "Qwen2.5 Coder 14B";
            };
            "deepseek-coder-v2:16b" = {
              id = "ollama_chat/deepseek-coder-v2:16b";
              displayName = "DeepSeek Coder V2 16B";
            };
          };
        };
      };
    };
    custom.sched_ext = {
      enable = true;
      scheduler = "scx_lavd";
    };

    custom.services.ollama = {
      enable = true;
      models = [
        "qwen2.5-coder:7b"
      ];
      providers.bob-local = {
        name = "Bob Local";
        baseURL = "http://localhost:11434/v1";
        models = {
          "qwen2.5-coder:7b" = {
            id = "ollama_chat/qwen2.5-coder:7b";
            displayName = "Qwen2.5 Coder 7B";
          };
        };
        visibility = "local";
      };
    };

    ## Run latest kernel for sched_ext
    boot.kernelPackages = pkgs.linuxPackages_latest;

    ## Impermanence
    custom.impermanence = {
      enable = true;

      userExtraFiles.jake = [
        ".ssh/id_ecdsa"
      ];
    };

    ## WiFi
    age.secrets."wifi/bob.lt.${config.ogygia.domain}".file = ../../secrets/wifi/bob.lt.${config.ogygia.domain}.age;
    networking.wireless = {
      enable = true;
      secretsFile = config.age.secrets."wifi/bob.lt.${config.ogygia.domain}".path;

      networks = {
        "Hillion WPA3 Network".pskRaw = "ext:HILLION_WPA3_NETWORK_PSK";
      };
    };

    ## Desktop
    custom.users.jake.password = true;
    custom.desktop.sway.enable = true;
    custom.games.steam.enable = true;

    security.sudo.wheelNeedsPassword = lib.mkForce true;

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/data/users/jake/sync";
    };

    ## Networking
    networking.firewall = {
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
    };
  };
}
