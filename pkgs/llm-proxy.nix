{ lib, rustPlatform, pkg-config, protobuf }:

rustPlatform.buildRustPackage {
  pname = "llm-proxy";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../rust-toolchain.toml
      (lib.fileset.fileFilter (f: f.hasExt "rs" || f.hasExt "toml") ../crates)
    ];
  };

  cargoLock.lockFile = ../Cargo.lock;

  nativeBuildInputs = [ pkg-config protobuf ];

  buildAndTestSubdir = "crates/llm-proxy";

  meta = {
    description = "Distributed LLM proxy sidecar with etcd-backed scheduling";
    license = lib.licenses.mit;
    mainProgram = "llm-proxy";
  };
}
