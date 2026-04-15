{ lib, stdenvNoCC, fetchFromGitHub, bun, cacert }:

let
  src = fetchFromGitHub {
    owner = "code-yeongyu";
    repo = "oh-my-openagent";
    rev = "80e73f5727ab5fe1902fabf3d6ca17380f58d555";
    hash = "sha256-93B8TcyMKELthz8Ml6/KPZqzzrExIkMIp6i2Jj5J8bk=";
  };

  bunDeps = stdenvNoCC.mkDerivation {
    name = "oh-my-openagent-deps-3.17.3";
    inherit src;

    nativeBuildInputs = [ bun cacert ];

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-+vnbK2jyScuZRfOc2Lwf239w/75HvM49wSqYs1/eNag=";

    dontFixup = true;

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      bun install --frozen-lockfile --no-progress --ignore-scripts
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -r node_modules $out
      runHook postInstall
    '';
  };
in
stdenvNoCC.mkDerivation {
  pname = "oh-my-openagent";
  version = "3.17.3";
  inherit src;

  nativeBuildInputs = [ bun ];

  dontFixup = true;

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR
    cp -r ${bunDeps} node_modules
    chmod -R u+w node_modules

    bun build src/index.ts --outdir dist --target bun --format esm --external @ast-grep/napi
    bun build src/cli/index.ts --outdir dist/cli --target bun --format esm --external @ast-grep/napi
    bun run script/build-schema.ts

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/oh-my-openagent
    cp -r dist $out/lib/oh-my-openagent/
    cp package.json $out/lib/oh-my-openagent/

    runHook postInstall
  '';

  meta = {
    description = "Multi-model agent orchestration harness for OpenCode";
    homepage = "https://github.com/code-yeongyu/oh-my-openagent";
  };
}
