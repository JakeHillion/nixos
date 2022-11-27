{ config, pkgs, lib, ... }:

{
  config.system.stateVersion = "22.05";

  config.networking.hostName = "gendry";
  config.networking.domain = "jakehillion-terminals.ts.hillion.co.uk";

  imports = [
    ../../modules/common/default.nix
    ./hardware-configuration.nix
  ];

  config.boot.loader.systemd-boot.enable = true;
  config.boot.loader.efi.canTouchEfiVariables = true;

  ## Tailscale
  config.age.secrets."tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk".file = ../../secrets/tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk.age;
  config.tailscalePreAuth = config.age.secrets."tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk".path;

  ## Password (for interactive logins)
  config.age.secrets."passwords/gendry.jakehillion-terminals.ts.hillion.co.uk/jake".file = ../../secrets/passwords/gendry.jakehillion-terminals.ts.hillion.co.uk/jake.age;
  config.users.users."jake".passwordFile = config.age.secrets."passwords/gendry.jakehillion-terminals.ts.hillion.co.uk/jake".path;

  config.security.sudo.wheelNeedsPassword = lib.mkForce true;

  ## Enable btrfs compression
  config.fileSystems."/data".options = [ "compress=zstd" ];
  config.fileSystems."/nix".options = [ "compress=zstd" ];

  ## Persist files (due to tmpfs root)
  ### Set root tmpfs to 0755
  config.fileSystems."/".options = [ "mode=0755" ];

  ### Require data at boot (to have access to host keys for agenix)
  config.fileSystems."/data".neededForBoot = true;

  ### OpenSSH Host Keys (SSH + agenix secrets)
  config.services.openssh = {
    hostKeys = [
      {
        path = "/data/system/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/data/system/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  ### Persistent directory symlinks
  config.systemd.tmpfiles.rules = [
    #### Persistent home subdirectories
    "L /root/local - - - - /data/users/root"
    "L /home/jake/local - - - - /data/users/jake"
  ];

  ### Persistent /etc/nixos
  config.fileSystems."/etc/nixos" = {
    device = "/data/users/root/repos/nixos";
    options = [ "bind" ];
  };

  ### Persistent zsh history
  config.programs.zsh.histFile = lib.mkForce "$HOME/local/.zsh_history";
}

