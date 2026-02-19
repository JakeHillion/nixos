{ lib, buildNpmPackage, nodejs }:

buildNpmPackage {
  pname = "opencode-plugin";
  version = "1.0.0";

  src = ./.;

  npmDepsHash = "sha256-voooRJ9NzLo/qmh9Iy3HdaB9bHGQnRsc/fDgdq7cSGA=";

  buildPhase = ''
    runHook preBuild
    npm run build
    runHook postBuild
  '';

  checkPhase = ''
    runHook preCheck
    npm test
    runHook postCheck
  '';
  doCheck = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/opencode-plugin
    cp -r dist $out/lib/opencode-plugin/
    cp package.json $out/lib/opencode-plugin/

    mkdir -p $out/bin
    cat > $out/bin/claude-hook-shim <<EOF
    #!/bin/sh
    exec ${nodejs}/bin/node $out/lib/opencode-plugin/dist/shim/claude-hook.js
    EOF
    chmod +x $out/bin/claude-hook-shim

    cat > $out/bin/claude-webfetch-hook-shim <<EOF
    #!/bin/sh
    exec ${nodejs}/bin/node $out/lib/opencode-plugin/dist/shim/claude-webfetch-hook.js
    EOF
    chmod +x $out/bin/claude-webfetch-hook-shim

    runHook postInstall
  '';

  meta = {
    description = "OpenCode plugin with Claude Code shim for Nix, jj, and cwd hooks";
    license = lib.licenses.mit;
  };
}
