{ pkgs, lib, config, ... }:

{
  users.users."jake".openssh.authorizedKeys.keyFiles = [ ./authorized_keys ];

  programs.mosh.enable = true;
  services.openssh = {
    enable = true;
    permitRootLogin = "no";
    passwordAuthentication = false;
  };
}
