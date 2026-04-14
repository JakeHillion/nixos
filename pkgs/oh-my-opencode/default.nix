{ lib, stdenv, oh-my-opencode }:

stdenv.mkDerivation {
  pname = "oh-my-opencode";
  version = "3.0.0";

  src = oh-my-opencode;

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/oh-my-opencode
    cp -r $src/dist $out/lib/oh-my-opencode/
    cp $src/package.json $out/lib/oh-my-opencode/

    runHook postInstall
  '';

  meta = {
    description = "Oh My OpenCode - Advanced plugin for OpenCode with async agents, LSP tools, and MCPs";
    homepage = "https://github.com/code-yeongyu/oh-my-opencode";
    license = lib.licenses.mit;
  };
}
