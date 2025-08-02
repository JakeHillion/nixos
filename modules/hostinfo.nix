{ pkgs, lib, config, ... }:

let
  cfg = config.custom.hostinfo;
  rev = config.system.configurationRevision;
  zkCfg = config.custom.services.zookeeper;
in
{
  options.custom.hostinfo = {
    enable = lib.mkEnableOption "hostinfo";
  };

  config = lib.mkIf cfg.enable {
    systemd.services.hostinfo = {
      description = "Expose hostinfo over HTTP.";

      wantedBy = [ "multi-user.target" ];

      script = "${pkgs.writers.writePerl "hostinfo" {
        libraries = with pkgs; [
          perlPackages.HTTPDaemon
        ];
      } ''
        use v5.10;
        use warnings;
        use strict;

        use HTTP::Daemon;
        use HTTP::Status;

        my $d = HTTP::Daemon->new(LocalPort => 30653) || die;
        while (my $c = $d->accept) {
          while (my $r = $c->get_request) {
            if ($r->method eq 'GET') {
              given ($r->uri->path) {
                when ('/current/nixos/system/configurationRevision') {
                  $c->send_file_response("/run/current-system/etc/flake-version");
                }
                when ('/booted/nixos/system/configurationRevision') {
                  $c->send_file_response("/run/booted-system/etc/flake-version");
                }
                when ('/nextboot/nixos/system/configurationRevision') {
                  $c->send_file_response("/nix/var/nix/profiles/system/etc/flake-version");
                }
                default {
                  $c->send_error(404);
                }
              }
            } else {
              $c->send_error(RC_FORBIDDEN);
            }
          }
          $c->close;
          undef($c);
        }
      ''}";

      serviceConfig = {
        DynamicUser = true;
        Restart = "always";
      };
    };

    systemd.services.hostinfo-zookeeper = {
      description = "Update ZooKeeper with system version information";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = pkgs.writers.writePython3 "hostinfo-zookeeper"
          {
            libraries = with pkgs.python3Packages; [ kazoo inotify-simple ];
          } ''
          import logging
          from pathlib import Path
          from inotify_simple import INotify, flags
          from kazoo.client import KazooClient
          from kazoo.exceptions import NodeExistsError, NoNodeError

          logging.basicConfig(
              level=logging.INFO,
              format='%(asctime)s - %(message)s'
          )
          logger = logging.getLogger(__name__)

          # Configuration
          ZK_HOSTS = "${zkCfg.clientConnectionString}"
          HOSTNAME = "${config.networking.fqdn}"

          STATE_MAPPING = {
              "/run/current-system": "current",
              "/run/booted-system": "booted",
              "/nix/var/nix/profiles/system": "nextboot"
          }


          def read_version_file(path):
              """Read version from flake-version file"""
              version_file = Path(path) / "etc" / "flake-version"
              try:
                  return version_file.read_text().strip()
              except Exception as e:
                  logger.debug(f"Could not read {version_file}: {e}")
              return None


          def update_zookeeper_node(zk, state, version, cached_versions):
              """Update or create a ZooKeeper node with version info if changed"""
              # Check if we already have this version cached
              if cached_versions.get(state) == version:
                  return False  # No change needed
              znode_path = f"/nixos/versions/{HOSTNAME}/{state}"
              logger.info(f"Updating {znode_path} = {version}")

              try:
                  # Try to set existing node first (most common case)
                  zk.set(znode_path, version.encode('utf-8'))
              except NoNodeError:
                  # Node doesn't exist, create it
                  zk.create(znode_path, version.encode('utf-8'))

              # Cache the version we just wrote
              cached_versions[state] = version
              return True  # Update was performed


          def load_existing_versions(zk, cached_versions):
              """Load existing versions from ZooKeeper into cache"""
              hostname_path = f"/nixos/versions/{HOSTNAME}"
              try:
                  existing_states = zk.get_children(hostname_path)
                  for state in existing_states:
                      znode_path = f"{hostname_path}/{state}"
                      try:
                          data, _ = zk.get(znode_path)
                          cached_versions[state] = data.decode('utf-8')
                          cached_val = cached_versions[state]
                          logger.debug(f"Cached existing {state} = {cached_val}")
                      except Exception as e:
                          logger.debug(f"Could not read {znode_path}: {e}")
              except Exception as e:
                  logger.debug(f"Could not list states for {hostname_path}: {e}")


          def update_all_versions(zk, cached_versions):
              """Update all version information in ZooKeeper if changed"""
              updates_made = 0
              for path, state in STATE_MAPPING.items():
                  version = read_version_file(path)
                  if version:
                      if update_zookeeper_node(zk, state, version, cached_versions):
                          updates_made += 1

              if updates_made > 0:
                  logger.info(f"Made {updates_made} ZooKeeper updates")
              else:
                  logger.debug("No ZooKeeper updates needed")


          def main():
              """Main function"""
              zk = KazooClient(hosts=ZK_HOSTS)
              cached_versions = {}

              try:
                  zk.start(timeout=10)
                  logger.info(f"Connected to ZooKeeper: {ZK_HOSTS}")

                  # Ensure hostname directory exists
                  hostname_path = f"/nixos/versions/{HOSTNAME}"
                  try:
                      zk.create(hostname_path, b"", makepath=True)
                      logger.info(f"Created hostname directory: {hostname_path}")
                  except NodeExistsError:
                      msg = f"Hostname directory already exists: {hostname_path}"
                      logger.debug(msg)

                  # Load existing versions into cache
                  load_existing_versions(zk, cached_versions)

                  # Set up inotify monitoring
                  with INotify() as inotify:
                      watch_descriptors = {}

                      for path in STATE_MAPPING:
                          if Path(path).exists():
                              watch_flags = (
                                  flags.CREATE | flags.DELETE |
                                  flags.MOVED_TO | flags.MOVED_FROM |
                                  flags.ATTRIB | flags.DONT_FOLLOW
                              )
                              wd = inotify.add_watch(path, watch_flags)
                              watch_descriptors[wd] = path
                              logger.info(f"Watching {path}")

                      # Initial update after inotify setup (only if changed)
                      update_all_versions(zk, cached_versions)

                      logger.info("Starting inotify watch for system changes")

                      # Watch for changes
                      for event in inotify.read():
                          path = watch_descriptors[event.wd]
                          msg = f"File system change detected: {path}"
                          logger.info(f"{msg} ({event.mask})")
                          update_all_versions(zk, cached_versions)
              finally:
                  zk.stop()


          if __name__ == "__main__":
              main()
        '';
        DynamicUser = true;
        Restart = "always";
        RestartSec = "10s";
      };
    };

    environment.etc = {
      flake-version = {
        source = builtins.toFile "flake-version" "${if rev == null then "dirty" else rev}";
        mode = "0444";
      };
    };
  };
}
