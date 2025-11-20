{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.ollama;
in
{
  options.custom.services.ollama = {
    enable = lib.mkEnableOption "ollama";

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/ollama";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Ollama models to pre-pull and keep available.";
    };

    providers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name for the provider";
          };

          baseURL = lib.mkOption {
            type = lib.types.str;
            description = "Base URL for the Ollama API";
          };

          models = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                id = lib.mkOption {
                  type = lib.types.str;
                  description = "Model ID for OpenCode (e.g., ollama_chat/qwen2.5-coder:14b)";
                };
                displayName = lib.mkOption {
                  type = lib.types.str;
                  description = "Human-readable model name";
                };
              };
            });
            default = {};
            description = "Models available from this provider";
          };

          visibility = lib.mkOption {
            type = lib.types.enum [ "global" "local" ];
            default = "global";
            description = "Whether this provider is accessible network-wide (global) or only localhost (local)";
          };
        };
      });
      default = {};
      description = "Ollama provider configurations for consumption by other services";
    };
  };

  config = lib.mkIf cfg.enable {
    custom.services.ollama.dataPath = lib.mkIf config.custom.impermanence.enable (lib.mkOverride 999 "${config.custom.impermanence.base}/services/ollama");

    users.users.ollama.uid = config.ids.uids.ollama;
    users.groups.ollama.gid = config.ids.gids.ollama;

    systemd.tmpfiles.rules = [ "d ${cfg.dataPath} 0700 ollama ollama - -" ];

    services.ollama = {
      enable = true;
      package = pkgs.ollama-rocm;
      acceleration = "rocm";
      rocmOverrideGfx = "11.0.0";

      home = cfg.dataPath;
      host = "[::]"; # not clear why this is necessary when reverse proxied

      user = "ollama";
      group = "ollama";

      # TODO: This downloads models with `ollama pull` but doesn't delete them when removed. This should be fixed.
      loadModels = cfg.models;
    };

    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        rocmPackages.clr.icd
        rocmPackages.rocm-runtime
      ];
    };

    custom.www.nebula = {
      enable = true;
      virtualHosts."http://ollama.${config.ogygia.domain}" = {
        extraConfig = ''
          reverse_proxy http://127.0.0.1:${toString config.services.ollama.port}
        '';
      };
    };
  };
}
