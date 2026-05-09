{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.llm_proxy;
  tomlFormat = pkgs.formats.toml { };

  configFile = tomlFormat.generate "llm-proxy.toml" {
    bind = "${cfg.bindAddress}:${toString cfg.port}";
    etcd.endpoints = config.custom.services.etcd.endpoints;
    scheduler = {
      backoff_initial_ms = cfg.backoff.initialMs;
      backoff_max_ms = cfg.backoff.maxMs;
      backoff_jitter = cfg.backoff.jitter;
      lease_ttl_secs = cfg.leaseTtlSecs;
    };
    providers = lib.mapAttrs
      (_: p: {
        url = p.url;
        api_key_credential = p.apiKeyCredential;
        models = p.models;
      })
      cfg.providers;
  };
in
{
  options.custom.services.llm_proxy = {
    enable = lib.mkEnableOption "llm-proxy LLM sidecar";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llm-proxy;
      description = "Package providing the llm-proxy binary.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind the HTTP listener.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "TCP port for the HTTP listener.";
    };

    leaseTtlSecs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
    };

    backoff = {
      initialMs = lib.mkOption {
        type = lib.types.ints.positive;
        default = 5000;
      };
      maxMs = lib.mkOption {
        type = lib.types.ints.positive;
        default = 300000;
      };
      jitter = lib.mkOption {
        type = lib.types.float;
        default = 0.25;
      };
    };

    providers = lib.mkOption {
      description = "Upstream provider definitions, keyed by logical name.";
      default = { };
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          url = lib.mkOption {
            type = lib.types.str;
            description = "Upstream OpenAI-compatible base URL (no trailing /chat/completions).";
          };
          apiKeyCredential = lib.mkOption {
            type = lib.types.str;
            description = ''
              Name of the systemd LoadCredential entry that holds this provider's
              API key. Resolved at runtime via $CREDENTIALS_DIRECTORY.
            '';
          };
          apiKeyFile = lib.mkOption {
            type = lib.types.path;
            description = ''
              Path to the file containing the API key. Loaded into systemd's
              credential store under apiKeyCredential.
            '';
          };
          models = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            description = "Mapping of logical model name -> upstream model name.";
            default = { };
          };
        };
      });
    };
  };

  config = lib.mkIf cfg.enable {
    custom.services.llm_proxy.providers = {
      canopywave = lib.mkDefault {
        url = "https://inference.canopywave.io/v1";
        apiKeyCredential = "canopywave-api-key";
        apiKeyFile = config.age.secrets."llm-proxy/canopywave-api-key".path;
        models = {
          "moonshotai/kimi-k2.6" = "moonshotai/kimi-k2.6";
          "minimax/minimax-m2.5" = "minimax/minimax-m2.5";
        };
      };
      ollama-cloud = lib.mkDefault {
        url = "https://ollama.com/v1";
        apiKeyCredential = "ollama-cloud-api-key";
        apiKeyFile = config.age.secrets."llm-proxy/ollama-cloud-api-key".path;
        models = {
          "zai/glm-5.1" = "glm-5.1";
          "deepseek/deepseek-v4-pro" = "deepseek-v4-pro";
        };
      };
    };

    age.secrets."llm-proxy/canopywave-api-key" = {
      rekeyFile = ./canopy-wave-unlimited.age;
    };
    age.secrets."llm-proxy/ollama-cloud-api-key" = {
      rekeyFile = ./ollama-cloud.age;
    };

    systemd.services.llm-proxy = {
      description = "LLM proxy sidecar with etcd-backed scheduling";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/llm-proxy";
        Restart = "always";
        RestartSec = "5s";

        DynamicUser = true;
        LoadCredential = lib.mapAttrsToList
          (_: p: "${p.apiKeyCredential}:${p.apiKeyFile}")
          cfg.providers;

        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
      };

      environment = {
        LLM_PROXY_CONFIG = "${configFile}";
        ETCD_ENDPOINTS = lib.concatStringsSep "," config.custom.services.etcd.endpoints;
        RUST_LOG = lib.mkDefault "info";
      };
    };
  };
}
