{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.git;
in
{
  options.custom.services.git = {
    enable = lib.mkEnableOption "git service (gitolite)";

    backup = lib.mkOption {
      default = true;
      type = lib.types.bool;
      description = "Enable backups to restic";
    };

  };

  config = lib.mkIf cfg.enable (
    let
      cgitPackage = pkgs.cgit;
      cgitFooter = pkgs.writeText "cgit-footer.html" ''
        <div class="footer">
          <p>Powered by cgit ${cgitPackage.version} and gitolite ${pkgs.gitolite.version}</p>
        </div>
      '';

      cgitConfig = pkgs.writeText "cgitrc" ''
        # Global settings
        virtual-root=/
        enable-http-clone=0
        clone-prefix=ssh://git@ssh.git.hillion.co.uk:3022/
        root-title=Hillion.co.uk Git repositories
        root-desc=Git repositories hosted at hillion.co.uk
      
        # Repository settings
        enable-index-owner=0
        enable-index-links=1
        enable-commit-graph=0
        enable-log-filecount=1
        enable-log-linecount=1
        max-stats=quarter
        branch-sort=age
      
        # UI settings
        footer=${cgitFooter}
        css=/cgit.css
        logo=/cgit.png
      
        # Security settings  
        enable-git-config=0
        snapshots=tar.gz tar.bz2 zip
      
        # Repository discovery
        # Respect git-daemon-export-ok files (only show public repos)
        strict-export=git-daemon-export-ok
        scan-path=${config.services.gitolite.dataDir}/repositories
        remove-suffix=1
      '';
    in
    {
      # Set up impermanence for git data
      services.gitolite.dataDir = lib.mkIf config.custom.impermanence.enable (lib.mkOverride 999 "${config.custom.impermanence.base}/services/git");

      # Create git data directory with proper permissions
      systemd.tmpfiles.rules = lib.mkIf config.custom.impermanence.enable [
        "d ${config.custom.impermanence.base}/services/git 0755 ${config.services.gitolite.user} ${config.services.gitolite.group} - -"
      ];

      # User and group configuration with static IDs
      users.users.git.uid = lib.mkForce config.ids.uids.git;
      users.groups.git.gid = lib.mkForce config.ids.gids.git;

      # Gitolite configuration
      services.gitolite = {
        enable = true;
        user = "git";
        group = "git";
        adminPubkey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOe6YuPo5/FsWaOWR4JHVrF9XQkeT4JE7TUici5ELQK/3/ngTL64JdRnVsf91piLQGyNRI3z2h18qGHQG+z55Zo= jake@merlin";
        extraGitoliteRc = ''
          push @{$RC{ENABLE}}, 'symbolic-ref';
        '';
      };

      # Backup configuration
      age.secrets."backups/git/restic/mig29" = lib.mkIf cfg.backup {
        rekeyFile = ../../secrets/restic/mig29.age;
        owner = config.services.gitolite.user;
        group = config.services.gitolite.group;
      };

      services.restic.backups."git" = lib.mkIf cfg.backup {
        user = config.services.gitolite.user;
        repository = "rest:https://restic.${config.ogygia.domain}/mig29";
        passwordFile = config.age.secrets."backups/git/restic/mig29".path;
        paths = [
          "${config.services.gitolite.dataDir}/repositories"
        ];
        timerConfig = {
          OnBootSec = "15m";
          OnUnitInactiveSec = "10m";
          RandomizedDelaySec = "5m";
        };
      };

      # fcgiwrap for CGI
      services.fcgiwrap = {
        instances.cgit = {
          process = {
            user = config.services.gitolite.user;
            group = config.services.gitolite.group;
          };
          socket = {
            type = "unix";
            address = "/run/fcgiwrap-cgit.sock";
            user = config.services.caddy.user;
            group = config.services.caddy.group;
            mode = "0600";
          };
        };
      };


      # Nebula reverse proxy configuration
      custom.www.nebula = {
        enable = true;
        virtualHosts."cgit.git.${config.ogygia.domain}" = {
          extraConfig = ''
            # Serve static assets
            handle /cgit.css {
              root * ${cgitPackage}/cgit
              file_server
            }
            
            handle /cgit.png {
              root * ${cgitPackage}/cgit
              file_server
            }

            # CGI handler for cgit
            handle {
              reverse_proxy unix///run/fcgiwrap-cgit.sock {
                transport fastcgi {
                  env SCRIPT_FILENAME ${cgitPackage}/cgit/cgit.cgi
                  env DOCUMENT_ROOT ${cgitPackage}/cgit
                  env SCRIPT_NAME /cgit.cgi
                  env CGIT_CONFIG ${cgitConfig}
                  env HTTP_HOST cgit.git.${config.ogygia.domain}
                }
              }
            }
          '';
        };
      };
    }
  );
}
