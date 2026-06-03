{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.gitea.actions-vm-burst;

  gcloud = pkgs.google-cloud-sdk;

  # The base runner qcow2 converted to GCE's upload format (a gzipped
  # tarball containing a single `disk.raw`). Done at Nix build time so
  # the artefact is content-addressed and shared across rebuilds.
  # `--mtime=@0` + `gzip -n` keep the output deterministic across builds.
  imageTarball = pkgs.runCommand "gitea-actions-vm-image-gce.tar.gz"
    {
      nativeBuildInputs = with pkgs; [ qemu-utils gnutar gzip ];
    } ''
    qemu-img convert -O raw ${pkgs.gitea-actions-vm-image}/image.qcow2 disk.raw
    tar -S --mtime=@0 --owner=0 --group=0 -cf - disk.raw \
      | gzip -n -9 > $out
  '';

  reconcileScript = pkgs.writers.writePython3 "gitea-actions-vm-burst-reconcile"
    {
      libraries = with pkgs.python3Packages; [ requests ];
    }
    (builtins.readFile ./reconcile.py);

  reconcileWrapper = pkgs.writeShellApplication {
    name = "gitea-actions-vm-burst-reconcile-wrapper";
    runtimeInputs = with pkgs; [ coreutils gcloud unstable.gitea-actions-runner xorriso gnutar gzip ];
    text = ''
      set -euo pipefail
      : "''${CREDENTIALS_DIRECTORY:?}"
      : "''${RUNTIME_DIRECTORY:?}"

      # gcloud writes config + auth cache under $HOME. With DynamicUser
      # the default $HOME is /, so redirect to the per-invocation runtime
      # dir; auth state is re-established each run from the SA key.
      export HOME="$RUNTIME_DIRECTORY"
      export CLOUDSDK_CONFIG="$RUNTIME_DIRECTORY/gcloud"
      mkdir -p "$CLOUDSDK_CONFIG"

      gcloud auth activate-service-account \
        --key-file="$CREDENTIALS_DIRECTORY/gcp-sa-key" --quiet
      gcloud config set project ${lib.escapeShellArg cfg.gcpProject} --quiet

      exec ${reconcileScript}
    '';
  };

  reposJson = builtins.toJSON cfg.repos;
  labelsCsv = lib.concatStringsSep "," cfg.labels;
in
{
  options.custom.services.gitea.actions-vm-burst = {
    enable = lib.mkEnableOption "burst-to-cloud Gitea Actions runners on GCP";

    gcpProject = lib.mkOption {
      type = lib.types.str;
      description = "GCP project ID that owns the burst VMs.";
    };

    gcpRegion = lib.mkOption {
      type = lib.types.str;
      default = "europe-north1";
      description = ''
        GCE region for burst VMs. The reconciler enumerates zones in the
        region and picks one randomly per VM, so individual zone outages
        affect throughput but not availability.
      '';
    };

    gcsBucket = lib.mkOption {
      type = lib.types.str;
      description = "GCS bucket used to stage the runner image and per-VM cidata tarballs.";
    };

    repos = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "JakeHillion/testquorum" ];
      description = "Gitea repos to monitor for queued jobs (owner/name).";
    };

    giteaUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://gitea.hillion.co.uk";
    };

    pollInterval = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Seconds between reconcile sweeps inside the daemon's main loop.";
    };

    jobAgeThreshold = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Only jobs queued for longer than this many seconds count toward the launch decision.";
    };

    maxInstances = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = "Hard cap on concurrent burst VMs.";
    };

    vcpus = lib.mkOption {
      type = lib.types.int;
      default = 6;
    };

    memoryMiB = lib.mkOption {
      type = lib.types.int;
      default = 12 * 1024;
    };

    bootDiskSizeGb = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = "Boot disk size; the image's rootfs is grown to fill this on first boot.";
    };

    maxRunDuration = lib.mkOption {
      type = lib.types.str;
      default = "13h";
      description = ''
        gcloud --max-run-duration value. After this elapses GCE force-stops
        the VM (lands in TERMINATED, which the reconciler then deletes), so
        a runner that wedges or never picks up a job can't burn credit
        indefinitely. Accepts gcloud duration syntax: 30m, 1h, 2h30m, etc.
      '';
    };

    labels = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ "ubuntu-26.04-vm" "ubuntu-vm" "ubuntu-26.04" ];
      description = "Runner labels advertised to Gitea. Matches the local actions-vm pool so jobs route to either substrate.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = (cfg.memoryMiB / 1024) * 1024 == cfg.memoryMiB;
      message = "actions-vm-burst.memoryMiB must be a whole number of GiB; N4 custom machine types are specified in MiB but Google rounds to GiB.";
    }];

    age.secrets."gitea-actions-vm-burst/registration-token" = {
      rekeyFile = ../actions-vm/token.age;
      mode = "0400";
    };
    age.secrets."gitea-actions-vm-burst/gitea-api-token" = {
      rekeyFile = ./gitea-api-token.age;
      mode = "0400";
    };
    age.secrets."gitea-actions-vm-burst/sa-key.json" = {
      rekeyFile = ./sa-key.json.age;
      mode = "0400";
    };

    systemd.services.gitea-actions-vm-burst = {
      description = "Burst Gitea Actions runners to GCP";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        Restart = "always";
        RestartSec = "30s";
        RuntimeDirectory = "gitea-actions-vm-burst";
        RuntimeDirectoryMode = "0700";
        LoadCredential = [
          "gitea-api-token:${config.age.secrets."gitea-actions-vm-burst/gitea-api-token".path}"
          "gitea-registration-token:${config.age.secrets."gitea-actions-vm-burst/registration-token".path}"
          "gcp-sa-key:${config.age.secrets."gitea-actions-vm-burst/sa-key.json".path}"
        ];
        ExecStart = lib.getExe reconcileWrapper;
      };
      environment = {
        GITEA_URL = cfg.giteaUrl;
        GITEA_REPOS = reposJson;
        JOB_AGE_THRESHOLD = toString cfg.jobAgeThreshold;
        MAX_INSTANCES = toString cfg.maxInstances;
        GCP_PROJECT = cfg.gcpProject;
        GCP_REGION = cfg.gcpRegion;
        GCS_BUCKET = cfg.gcsBucket;
        MACHINE_TYPE = "n4-custom-${toString cfg.vcpus}-${toString cfg.memoryMiB}";
        BOOT_DISK_SIZE_GB = toString cfg.bootDiskSizeGb;
        MAX_RUN_DURATION = cfg.maxRunDuration;
        RUNNER_LABELS = labelsCsv;
        IMAGE_TARBALL = "${imageTarball}";
        POLL_INTERVAL = toString cfg.pollInterval;
      };
    };
  };
}
