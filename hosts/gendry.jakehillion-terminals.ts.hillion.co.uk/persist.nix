{ config, pkgs, lib, ... }:

{
  # Persist files (due to tmpfs root)
  ## Set root tmpfs to 0755
  fileSystems."/".options = [ "mode=0755" ];

  ## Require data at boot (to have access to host keys for agenix)
  fileSystems."/data".neededForBoot = true;

  ## OpenSSH Host Keys (SSH + agenix secrets)
  services.openssh = {
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

  ## Persistent directories and symlinks
  systemd.tmpfiles.rules = [
    ### Persistent home subdirectories
    "L /root/local - - - - /data/users/root"
    "L /home/jake/local - - - - /data/users/jake"

    ### Persistent SSH keys
    "L /home/jake/.ssh/id_rsa - - - - /data/users/jake/.ssh/id_rsa"
    "L /home/jake/.ssh/id_ecdsa - - - - /data/users/jake/.ssh/id_ecdsa"

    ### Persistent spotify-tui
    "d /home/jake/.config/ 0700 jake users - -"
    "d /home/jake/.config/spotify-tui/ 0700 jake users - -"
    "L /home/jake/.config/spotify-tui/.spotify_token_cache.json - - - - /data/users/jake/.config/spotify-tui/.spotify_token_cache.json"
    "L /home/jake/.config/spotify-tui/client.yml - - - - /data/users/jake/.config/spotify-tui/client.yml"
  ];

  ## Persistent /etc/nixos
  fileSystems."/etc/nixos" = {
    device = "/data/users/root/repos/nixos";
    options = [ "bind" ];
  };

  ## Persistent zsh history
  programs.zsh.histFile = lib.mkForce "$HOME/local/.zsh_history";

  ## Tailscale
  fileSystems."/var/lib/tailscale" = {
    device = "/data/system/var/lib/tailscale";
    options = [ "bind" ];
  };

  ## Bluetooth
  fileSystems."/var/lib/bluetooth" = {
    device = "/data/system/var/lib/bluetooth";
    options = [ "bind" ];
  };

  ## Minecraft
  fileSystems."/home/jake/.local/share/PrismLauncher" = {
    device = "/data/users/jake/.local/share/PrismLauncher";
    options = [ "bind" ];
  };
}
