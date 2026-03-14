{ lib, stdenv, go, xcaddy, cacert, git, caddy }:

let
  # Local plugin source
  jakehillionPlugin = ./caddy-dns-jakehillion;

  # Remote plugins with versions
  cloudflarePlugin = "github.com/caddy-dns/cloudflare@v0.2.1";

  version = caddy.version;
in
caddy.overrideAttrs (finalAttrs: prevAttrs: {
  pname = "caddy-with-dns";
  vendorHash = null;
  subPackages = [ "." ];

  src = stdenv.mkDerivation {
    pname = "caddy-src-with-dns-plugins";
    inherit version;

    nativeBuildInputs = [
      go
      xcaddy
      cacert
      git
    ];

    dontUnpack = true;

    buildPhase = ''
      export GOCACHE=$TMPDIR/go-cache
      export GOPATH="$TMPDIR/go"

      # Build Caddy source with cloudflare plugin
      XCADDY_SKIP_BUILD=1 TMPDIR="$PWD" xcaddy build v${version} \
        --with ${cloudflarePlugin}

      cd buildenv*

      # Copy local plugin to a location outside vendor
      mkdir -p local-plugins/github.com/jakehillion
      cp -r ${jakehillionPlugin} local-plugins/github.com/jakehillion/caddy-dns-jakehillion
      chmod -R u+w local-plugins

      # Add import for our plugin to main.go (xcaddy generates main.go at root)
      sed -i 's|import (|import (\n\t_ "github.com/jakehillion/caddy-dns-jakehillion"|' main.go

      # Update go.mod to include local plugin with replacement pointing outside vendor
      echo 'require github.com/jakehillion/caddy-dns-jakehillion v0.0.0' >> go.mod
      echo 'replace github.com/jakehillion/caddy-dns-jakehillion => ./local-plugins/github.com/jakehillion/caddy-dns-jakehillion' >> go.mod

      # Resolve transitive dependencies from local plugin, then vendor
      go mod tidy
      go mod vendor
    '';

    installPhase = ''
      cd ..
      mv buildenv* $out
    '';

    outputHashMode = "recursive";
    outputHash = "sha256-KoOCBdFYqsfbw/vNDr4GXDNmZtAbgoLqiuP9d7pu35Q=";
    outputHashAlgo = "sha256";
  };

  # Skip install check since we have a local plugin
  doInstallCheck = false;
})
