{ stdenv, lib, fetchFromGitHub, rustPlatform, pkg-config, llvmPackages, elfutils, zlib, ... }:

rustPlatform.buildRustPackage rec {
  pname = "scx_layered";

  src = fetchFromGitHub {
    owner = "sched-ext";
    repo = "scx";
    rev = "d8150c1913890c79b408073f95e094285b5b4927";
    hash = "sha256-Pd5h890jOyrOL0hIiRG91nlCST6cvhT8wpDTTGP3b74=";
  };
  version = "1.0.5-dirty";

  cargoRoot = "scheds/rust/scx_layered";
  cargoLock.lockFile = ./Cargo.lock;

  postPatch = ''
    rm Cargo.toml Cargo.lock
    ln -fs ${./Cargo.lock} scheds/rust/scx_layered/Cargo.lock
  '';

  nativeBuildInputs = [ pkg-config llvmPackages.clang ];
  buildInputs = [ elfutils zlib ];

  LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";

  preBuild = ''
    cd scheds/rust/scx_layered
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp target/${stdenv.targetPlatform.config}/release/scx_layered $out/bin/

    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://github.com/sched-ext/scx";
    description = "scx_layered sched_ext userspace scheduler";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
    maintainers = [{
      email = "jake@hillion.co.uk";
      matrix = "@jake:hillion.co.uk";
      name = "Jake Hillion";
      github = "JakeHillion";
      githubId = 5712856;
    }];
  };
}
