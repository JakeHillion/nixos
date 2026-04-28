{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.openwebui;
in
{
  options.custom.services.openwebui = {
    enable = lib.mkEnableOption "openwebui";
  };

  config = lib.mkIf cfg.enable {
    users.users.open-webui = {
      uid = config.ids.uids.open-webui;
      isSystemUser = true;
      group = "open-webui";
    };
    users.groups.open-webui = {
      gid = config.ids.gids.open-webui;
    };

    systemd.services.open-webui.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "open-webui";
      Group = "open-webui";
    };

    services.open-webui = {
      enable = true;
      host = "127.0.0.1";
      port = 38269;
      package = pkgs.open-webui.overridePythonAttrs (old: {
        dependencies = old.dependencies ++ old.optional-dependencies.postgres;
      });
      stateDir = lib.mkIf config.custom.impermanence.enable
        (lib.mkOverride 999 "${config.custom.impermanence.base}/services/open-webui");
      environment = {
        DATABASE_URL = "postgresql:///open-webui?host=/run/postgresql";
        PGVECTOR_DB_URL = "postgresql:///open-webui?host=/run/postgresql";
        VECTOR_DB = "pgvector";
        ENABLE_OLLAMA_API = "False";
        ENABLE_PERSISTENT_CONFIG = "False";
        WEBUI_URL = "https://openwebui.${config.ogygia.domain}";
        SCARF_NO_ANALYTICS = "True";
        DO_NOT_TRACK = "True";
        ANONYMIZED_TELEMETRY = "False";
        OPENAI_API_BASE_URLS = "https://inference.canopywave.io/v1";
        OPENAI_API_MODELS = "moonshotai/kimi-k2.6,minimax/minimax-m2.5";
        ENABLE_WEB_SEARCH = "True";
        WEB_SEARCH_ENGINE = "searxng";
        SEARXNG_QUERY_URL = "https://searxng.${config.ogygia.domain}/search?q=<query>";
        WEB_SEARCH_RESULT_COUNT = "5";
        WEB_SEARCH_CONCURRENT_REQUESTS = "10";
        RAG_EMBEDDING_MODEL = "BAAI/bge-large-en-v1.5";
        CHUNK_SIZE = "4000";
        CHUNK_OVERLAP = "400";
        RAG_TOP_K = "30";
        ENABLE_RAG_HYBRID_SEARCH = "True";
      };
    };

    age.secrets."openwebui/canopywave-api-key" = {
      rekeyFile = ../../../secrets/ai/canopy-wave-unlimited.age;
    };

    services.postgresql = {
      enable = true;
      ensureDatabases = [ "open-webui" ];
      ensureUsers = [{
        name = "open-webui";
        ensureDBOwnership = true;
      }];
      extensions = ps: [ ps.pgvector ];
    };

    systemd.services.open-webui-pgvector-init = {
      description = "Create pgvector extension for OpenWebUI";
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
      };
      script = ''
        ${config.services.postgresql.package}/bin/psql -d open-webui -c "CREATE EXTENSION IF NOT EXISTS vector;"
      '';
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      before = [ "open-webui.service" ];
      wantedBy = [ "open-webui.service" ];
    };

    systemd.services.open-webui-env = {
      description = "Generate OpenWebUI environment file with API key";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        mkdir -p /run/open-webui
        {
          echo "OPENAI_API_KEYS=$(cat ${config.age.secrets."openwebui/canopywave-api-key".path})"
        } > /run/open-webui/env
        chown open-webui:open-webui /run/open-webui/env
        chmod 600 /run/open-webui/env
      '';
      after = [ "open-webui-pgvector-init.service" ];
      before = [ "open-webui.service" ];
      wantedBy = [ "open-webui.service" ];
    };

    systemd.services.open-webui = {
      after = [ "open-webui-env.service" "open-webui-pgvector-init.service" "postgresql-setup.service" ];
      requires = [ "open-webui-env.service" "open-webui-pgvector-init.service" "postgresql-setup.service" ];
      serviceConfig.EnvironmentFile = lib.mkForce "/run/open-webui/env";
    };

    systemd.tmpfiles.rules = lib.mkIf config.custom.impermanence.enable [
      "d ${config.custom.impermanence.base}/services/open-webui 0700 open-webui open-webui - -"
    ];

    custom.www.nebula = {
      enable = true;
      virtualHosts."openwebui.${config.ogygia.domain}" = {
        extraConfig = ''
          reverse_proxy http://127.0.0.1:${toString config.services.open-webui.port}
        '';
      };
    };

    services.postgresqlBackup = {
      enable = true;
      compression = "none";
      databases = [ "open-webui" ];
    };

    age.secrets."backups/openwebui/restic/mig29" = {
      rekeyFile = ../../../secrets/restic/mig29.age;
    };
    services.restic.backups."openwebui" = {
      user = "root";
      timerConfig = {
        OnCalendar = "03:30";
        RandomizedDelaySec = "60m";
      };
      repository = "rest:https://restic.${config.ogygia.domain}/mig29";
      passwordFile = config.age.secrets."backups/openwebui/restic/mig29".path;
      paths = [
        "${config.services.postgresqlBackup.location}/open-webui.sql"
        config.services.open-webui.stateDir
      ];
    };
  };
}
