{ lib, stdenvNoCC, buildNpmPackage, fetchNpmDeps, openclaw-gateway, nodejs, jq, cacert, matrix-sdk-crypto-nodejs }:

let
  src = "${openclaw-gateway.src}/extensions/matrix";

  # Generate package-lock.json from upstream package.json with devDeps stripped.
  # This is a FOD so it has network access to resolve versions from the registry.
  packageLock = stdenvNoCC.mkDerivation {
    name = "openclaw-matrix-package-lock.json";
    inherit src;
    nativeBuildInputs = [ nodejs jq ];
    postPatch = ''
      ${lib.getExe jq} 'del(.devDependencies)' package.json > package.json.tmp
      mv package.json.tmp package.json
    '';
    buildPhase = ''
      export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
      export NODE_EXTRA_CA_CERTS="${cacert}/etc/ssl/certs/ca-bundle.crt"
      HOME=$TMPDIR npm install --package-lock-only
    '';
    installPhase = ''
      mv package-lock.json $out
    '';
    outputHashAlgo = "sha256";
    outputHashMode = "flat";
    outputHash = "sha256-aJU115X/8E2d12ltz+vhTifxzPeiG4BvmwQsOFOBNLw=";
  };

  postPatch = ''
    ${lib.getExe jq} 'del(.devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
    cp ${packageLock} package-lock.json
  '';
in
buildNpmPackage {
  pname = "openclaw-matrix-plugin";
  inherit (openclaw-gateway) version;
  inherit src postPatch;

  npmDeps = fetchNpmDeps {
    inherit src postPatch;
    name = "openclaw-matrix-plugin-npm-deps";
    hash = "sha256-RrEQ/BzawMdyPPJOKdSb4YOIsGOUhqX8tKBsJGksN98=";
  };

  dontBuild = true; # jiti loads TypeScript directly

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r . $out/

    # The npm-installed @matrix-org/matrix-sdk-crypto-nodejs tries to load a
    # platform-specific native package that doesn't exist in the npm registry
    # build. Copy the native .node binary from nixpkgs which bundles it inline.
    cp ${matrix-sdk-crypto-nodejs}/lib/node_modules/@matrix-org/matrix-sdk-crypto-nodejs/matrix-sdk-crypto.*.node \
      $out/node_modules/@matrix-org/matrix-sdk-crypto-nodejs/

    runHook postInstall
  '';

  meta = {
    description = "OpenClaw Matrix channel plugin";
    license = lib.licenses.mit;
  };
}
