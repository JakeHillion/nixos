{ lib, stdenv, makeWrapper, opencode, opencode-plugin, oh-my-opencode, nodejs }:

stdenv.mkDerivation {
  pname = "opencode-with-plugins";
  version = opencode.version;

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    mkdir -p $out/lib/opencode-plugins

    # Link the plugins to a known location
    ln -s ${opencode-plugin}/lib/opencode-plugin $out/lib/opencode-plugins/opencode-plugin
    ln -s ${oh-my-opencode}/lib/oh-my-opencode $out/lib/opencode-plugins/oh-my-opencode

    # Create a wrapped opencode that includes nodejs in PATH (needed for plugins)
    makeWrapper ${opencode}/bin/opencode $out/bin/opencode \
      --prefix PATH : ${nodejs}/bin

    # Copy any other binaries from the original package
    for bin in ${opencode}/bin/*; do
      if [ "$(basename $bin)" != "opencode" ]; then
        ln -s $bin $out/bin/$(basename $bin)
      fi
    done

    runHook postInstall
  '';

  passthru = {
    inherit opencode-plugin oh-my-opencode;
  };

  meta = {
    description = "OpenCode bundled with custom plugin and oh-my-opencode";
    inherit (opencode.meta) license;
  };
}
