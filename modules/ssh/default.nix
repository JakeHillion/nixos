{ pkgs, lib, config, ... }:

let
  cfg = config.custom.ssh;
  hostKeys = import ./host-keys.nix;
in
{
  options.custom.ssh = {
    enable = lib.mkEnableOption "ssh";
  };

  config = lib.mkIf cfg.enable {
    programs.mosh.enable = true;

    services.openssh = {
      enable = true;
      openFirewall = true;

      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };
    services.fail2ban = {
      enable = true;
      ignoreIP = [ "172.20.0.0/24" ];
      bantime = "1h";
      bantime-increment.enable = true;
    };

    users.users =
      if config.custom.user == "jake" then {
        "jake".openssh.authorizedKeys.keys = import ./authorized-keys.nix;
      } else { };

    programs.ssh.knownHosts = {
      # Global Internet hosts
      "ssh.gitea.hillion.co.uk".publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCxQpywsy+WGeaEkEL67xOBL1NIE++pcojxro5xAPO6VQe2N79388NRFMLlX6HtnebkIpVrvnqdLOs0BPMAokjaWCC4Ay7T/3ko1kXSOlqHY5Ye9jtjRK+wPHMZgzf74a3jlvxjrXJMA70rPQ3X+8UGpA04eB3JyyLTLuVvc6znMe53QiZ0x+hSz+4pYshnCO2UazJ148vV3htN6wRK+uqjNdjjQXkNJ7llNBSrvmfrLidlf0LRphEk43maSQCBcLEZgf4pxXBA7rFuZABZTz1twbnxP2ziyBaSOs7rcII+jVhF2cqJlElutBfIgRNJ3DjNiTcdhNaZzkwJ59huR0LUFQlHI+SALvPzE9ZXWVOX/SqQG+oIB8VebR52icii0aJH7jatkogwNk0121xmhpvvR7gwbJ9YjYRTpKs4lew3bq/W/OM8GF/FEuCsCuNIXRXKqIjJVAtIpuuhxPymFHeqJH3wK3f6jTJfcAz/z33Rwpow2VOdDyqrRfAW8ti73CCnRlN+VJi0V/zvYGs9CHldY3YvMr7rSd0+fdGyJHSTSRBF0vcyRVA/SqSfcIo/5o0ssYoBnQCg6gOkc3nNQ0C0/qh1ww17rw4hqBRxFJ2t3aBUMK+UHPxrELLVmG6ZUmfg9uVkOoafjRsoML6DVDB4JAk5JsmcZhybOarI9PJfEQ==";

      # CNAME records
      "restic.${config.ogygia.domain}".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE9AAAAIBPQcp9MzabvwbViNmILVNfipMUnwV+5okRfhOuV7+Mt";

      # Network devices
      ${config.custom.network.devices.es-16-xg.net.lan.ipv4}.publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBN8FlrBGFXrPBmP0Tty9hhKzNYJNKek9wcNyjZZ1hkmHI747FJdBJmcf+yW9q/dnJ+AA0mfHQrEFl0qwc+w/Ko8=";
      ${config.custom.network.devices.es-48-500w.net.lan.ipv4}.publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGm4OeCoCYbpE/2oU9teWKpQsK17aCQM9mJ7esFNfPndjpRrb9yfszqY0QfEXo5xagbfRGYfk2OzpL1tlJZzqRA=";
    } // builtins.mapAttrs (_: key: { publicKey = key; }) hostKeys.byFqdn;
    programs.ssh.knownHostsFiles = [ ./github_known_hosts ];
  };
}
