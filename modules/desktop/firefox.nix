{ config, lib, pkgs, ... }:

let
  cfg = config.custom.desktop.firefox;
in
{
  options.custom.desktop.firefox = {
    enable = lib.mkEnableOption "Firefox";

    defaultBrowser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Set Firefox as the default browser";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.firefox = {
      enable = true;
      package = pkgs.firefox;

      policies = {
        ExtensionSettings = {
          "uBlock0@raymondhill.net" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          };
          "treestyletab@piro.sakura.ne.jp" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/tree-style-tab/latest.xpi";
          };
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          };
          "consent-o-matic@eff.org" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/consent-o-matic/latest.xpi";
          };
          "sponsorBlocker@ajay.app" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
            storage = {
              # What categories to skip: sponsor=auto-skip, poi_highlight=highlight, others=disabled
              categorySelections = [
                { name = "sponsor"; option = 2; }
                { name = "poi_highlight"; option = 1; }
                { name = "exclusive_access"; option = 0; }
                { name = "chapter"; option = 0; }
                { name = "selfpromo"; option = 2; }
              ];

              # Enable skipping for these categories
              permissions = {
                sponsor = true;
                selfpromo = true;
                exclusive_access = true;
                interaction = true;
                intro = true;
                outro = true;
                preview = true;
                hook = true;
                music_offtopic = true;
                filler = true;
                poi_highlight = true;
                chapter = false;
              };
            };
          };
          "tabreloader@kaze" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/tab-reloader/latest.xpi";
          };
        };

        "3rdparty".Extensions = {
          "treestyletab@piro.sakura.ne.jp" = {
            "autohide.tabbar.enabled" = true;
            "autohide.tabbar.delay.show" = 0;
            "autohide.tabbar.delay.hide" = 0;
          };
        };

        Preferences = {
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "browser.compactmode.show" = true;
          # Disable Firefox password manager
          "signon.rememberSignons" = false;
          "signon.autofillForms" = false;
          "signon.schemeUpgrades" = false;
        };
      };
    };

    # Set default browser
    environment.sessionVariables = {
      DEFAULT_BROWSER = "${pkgs.firefox}/bin/firefox";
    };

    # Add to system packages for clickable links
    environment.systemPackages = [ pkgs.firefox ];

    # Configure Firefox with home-manager
    home-manager.users.${config.custom.user} = {
      programs.firefox = {
        enable = true;

        profiles.default = {
          isDefault = true;
          search = {
            default = "ddg";
          };
          settings = {
            "browser.startup.homepage" = "https://app.todoist.com/app/today";
          };
          userChrome = ''
            /* Hide main tabs toolbar when Tree Style Tab is enabled */
            #TabsToolbar {
              visibility: collapse !important;
            }

            /* Hide the sidebar header when Tree Style Tab is active */
            #sidebar-box[sidebarcommand="treestyletab_piro_sakura_ne_jp-sidebar-action"] #sidebar-header {
              visibility: collapse !important;
            }

            /* Adjust tree style tab sidebar width */
            #sidebar-box {
              min-width: 200px !important;
              max-width: 400px !important;
            }

            /* Hide the title bar to save space */
            #titlebar {
              visibility: collapse !important;
            }
          '';
        };
      };

      # Force home-manager to destroy search.json.mozlz4 if Firefox modifies it
      home.file.".mozilla/firefox/default/search.json.mozlz4".force = lib.mkForce true;
    };

    # Impermanence configuration
    custom.impermanence.userExtraDirs = {
      ${config.custom.user} = [
        ".mozilla"
      ];
    };
  };
}
