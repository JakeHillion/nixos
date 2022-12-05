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

  ## Persistent directory symlinks
  systemd.tmpfiles.rules = [
    ### Persistent home subdirectories
    "L /root/local - - - - /data/users/root"
    "L /home/jake/local - - - - /data/users/jake"
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
}
