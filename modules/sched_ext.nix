{ config, pkgs, lib, ... }:

let
  cfg = config.custom.sched_ext;
in
{
  options.custom.sched_ext = {
    enable = lib.mkEnableOption "sched_ext";
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages =
      let
        linux_6_12_pkg = { fetchFromGitHub, buildLinux, ... } @ args:
          buildLinux (args // rec {
            version = "6.11.0"; # trying to fix "Error: modDirVersion 6.12 specified in the Nix expression is wrong, it should be: 6.11.0", this is really a 6.12 pre-release
            modDirVersion = version;

            src = fetchFromGitHub {
              owner = "torvalds";
              repo = "linux";
              rev = "88264981f2082248e892a706b2c5004650faac54"; # sched_ext merge in 6.12 merge window
              hash = "sha256-k+Mnzb8QFCOaoavBa16XHPVPz7vX2YcuTQpvec8sR6k=";
            };

            extraConfig = ''
              BPF y
              BPF_EVENTS y
              BPF_JIT y
              BPF_SYSCALL y
              DEBUG_INFO_BTF y
              FTRACE y
              SCHED_CLASS_EXT y
            '';

            ignoreConfigErrors = true;
          } // (args.argsOverride or { }));
        linux_6_12 = pkgs.callPackage linux_6_12_pkg { };
      in
      pkgs.recurseIntoAttrs (pkgs.linuxPackagesFor linux_6_12);
  };
}

