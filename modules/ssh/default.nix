{ pkgs, lib, config, ... }:

let
  cfg = config.custom.ssh;
in
{
  options.custom.ssh = {
    enable = lib.mkEnableOption "ssh";
  };

  config = lib.mkIf cfg.enable {
    users.users =
      if config.custom.user == "jake" then {
        "jake".openssh.authorizedKeys.keys = [
          "sk-ecdsa-sha2-nistp256@openssh.com AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBBwJH4udKNvi9TjOBgkxpBBy7hzWqmP0lT5zE9neusCpQLIiDhr6KXYMPXWXdZDc18wH1OLi2+639dXOvp8V/wgAAAAEc3NoOg== jake@beryllium-keys"

          "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOt74U+rL+BMtAEjfu/Optg1D7Ly7U+TupRxd5u9kfN7oJnW4dJA25WRSr4dgQNq7MiMveoduBY/ky2s0c9gvIA= jake@jake-gentoo"
          "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBC0uKIvvvkzrOcS7AcamsQRFId+bqPwUC9IiUIsiH5oWX1ReiITOuEo+TL9YMII5RyyfJFeu2ZP9moNuZYlE7Bs= jake@jake-mbp"

          "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAyFsYYjLZ/wyw8XUbcmkk6OKt2IqLOnWpRE5gEvm3X0V4IeTOL9F4IL79h7FTsPvi2t9zGBL1hxeTMZHSGfrdWaMJkQp94gA1W30MKXvJ47nEVt0HUIOufGqgTTaAn4BHxlFUBUuS7UxaA4igFpFVoPJed7ZMhMqxg+RWUmBAkcgTWDMgzUx44TiNpzkYlG8cYuqcIzpV2dhGn79qsfUzBMpGJgkxjkGdDEHRk66JXgD/EtVasZvqp5/KLNnOpisKjR88UJKJ6/buV7FLVra4/0hA9JtH9e1ecCfxMPbOeluaxlieEuSXV2oJMbQoPP87+/QriNdi/6QuCHkMDEhyGw== jake@jake-mbp"
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCw4lgH20nfuchDqvVf0YciqN0GnBw5hfh8KIun5z0P7wlNgVYnCyvPvdIlGf2Nt1z5EGfsMzMLhKDOZkcTMlhupd+j2Er/ZB764uVBGe1n3CoPeasmbIlnamZ12EusYDvQGm2hVJTGQPPp9nKaRxr6ljvTMTNl0KWlWvKP4kec74d28MGgULOPLT3HlAyvUymSULK4lSxFK0l97IVXLa8YwuL5TNFGHUmjoSsi/Q7/CKaqvNh+ib1BYHzHYsuEzaaApnCnfjDBNexHm/AfbI7s+g3XZDcZOORZn6r44dOBNFfwvppsWj3CszwJQYIFeJFuMRtzlC8+kyYxci0+FXHn jake@jake-gentoo"
        ];
      } else { };

    programs.mosh.enable = true;
    services.openssh = {
      enable = true;
      openFirewall = true;

      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };

    programs.ssh.knownHosts = {
      # Global Internet hosts
      "ssh.gitea.hillion.co.uk".publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCxQpywsy+WGeaEkEL67xOBL1NIE++pcojxro5xAPO6VQe2N79388NRFMLlX6HtnebkIpVrvnqdLOs0BPMAokjaWCC4Ay7T/3ko1kXSOlqHY5Ye9jtjRK+wPHMZgzf74a3jlvxjrXJMA70rPQ3X+8UGpA04eB3JyyLTLuVvc6znMe53QiZ0x+hSz+4pYshnCO2UazJ148vV3htN6wRK+uqjNdjjQXkNJ7llNBSrvmfrLidlf0LRphEk43maSQCBcLEZgf4pxXBA7rFuZABZTz1twbnxP2ziyBaSOs7rcII+jVhF2cqJlElutBfIgRNJ3DjNiTcdhNaZzkwJ59huR0LUFQlHI+SALvPzE9ZXWVOX/SqQG+oIB8VebR52icii0aJH7jatkogwNk0121xmhpvvR7gwbJ9YjYRTpKs4lew3bq/W/OM8GF/FEuCsCuNIXRXKqIjJVAtIpuuhxPymFHeqJH3wK3f6jTJfcAz/z33Rwpow2VOdDyqrRfAW8ti73CCnRlN+VJi0V/zvYGs9CHldY3YvMr7rSd0+fdGyJHSTSRBF0vcyRVA/SqSfcIo/5o0ssYoBnQCg6gOkc3nNQ0C0/qh1ww17rw4hqBRxFJ2t3aBUMK+UHPxrELLVmG6ZUmfg9uVkOoafjRsoML6DVDB4JAk5JsmcZhybOarI9PJfEQ==";

      # Tailscale hosts
      "boron.cx.ts.hillion.co.uk".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDtcJ7HY/vjtheMV8EN2wlTw1hU53CJebGIeRJcSkzt5";
      "be.lt.ts.hillion.co.uk".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILV3OSUT+cqFqrFHZGfn7/xi5FW3n1qjUFy8zBbYs2Sm";
      "dancefloor.dancefloor.ts.hillion.co.uk".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXkGueVYKr2wp/VHo2QLis0kmKtc/Upg3pGoHr6RkzY";
      "gendry.jakehillion.terminals.ts.hillion.co.uk".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPXM5aDvNv4MTITXAvJWSS2yvr/mbxJE31tgwJtcl38c";
      "homeassistant.homeassistant.ts.hillion.co.uk".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPM2ytacl/zYXhgvosvhudsl0zW5eQRHXm9aMqG9adux";
      "li.pop.ts.hillion.co.uk".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQWgcDFL9UZBDKHPiEGepT1Qsc4gz3Pee0/XVHJ6V6u";
      "microserver.home.ts.hillion.co.uk".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPPOCPqXm5a+vGB6PsJFvjKNgjLhM5MxrwCy6iHGRjXw";
      "router.home.ts.hillion.co.uk".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlCj/i2xprN6h0Ik2tthOJQy6Qwq3Ony73+yfbHYTFu";
      "theon.storage.ts.hillion.co.uk".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN59psLVu3/sQORA4x3p8H3ei8MCQlcwX5T+k3kBeBMf";
      "tywin.storage.ts.hillion.co.uk".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGATsjWO0qZNFp2BhfgDuWi+e/ScMkFxp79N2OZoed1k";
    };
    programs.ssh.knownHostsFiles = [ ./github_known_hosts ];
  };
}
