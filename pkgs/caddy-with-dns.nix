{ lib, buildGoModule, caddy }:

let
  src = ./caddy-dns-jakehillion;

  # Caddy's version comes from the module's go.mod rather than nixpkgs, so
  # nixpkgs updates never change the vendored dependencies.
  version = lib.removePrefix "v" (builtins.head (builtins.match
    ".*[[:space:]]github.com/caddyserver/caddy/v2 (v[^[:space:]]+).*"
    (builtins.readFile "${src}/go.mod")));
in
buildGoModule {
  pname = "caddy-with-dns";
  inherit version src;

  vendorHash = "sha256-QxR/GZotZb3VDcLyokrYT6HGvVD9aoJP0/rlXfyuVrM=";

  subPackages = [ "cmd/caddy" ];

  ldflags = [
    "-s"
    "-X github.com/caddyserver/caddy/v2.CustomVersion=v${version}"
  ];

  tags = [
    "nobadger"
    "nomysql"
    "nopgx"
  ];

  # Use only the system CA store. The embedded fallback bundle does not get cacert updates.
  postConfigure = ''
    chmod u+w vendor/github.com/caddyserver/caddy/v2/cmd
    rm vendor/github.com/caddyserver/caddy/v2/cmd/x509rootsfallback.go
  '';

  # The NixOS module loads the units through systemd.packages.
  postInstall = ''
    install -Dm644 ${caddy.dist}/init/caddy.service ${caddy.dist}/init/caddy-api.service -t $out/lib/systemd/system

    substituteInPlace $out/lib/systemd/system/caddy.service $out/lib/systemd/system/caddy-api.service \
      --replace-fail "/usr/bin/caddy" "$out/bin/caddy"
  '';

  meta = {
    inherit (caddy.meta) homepage license;
    description = "Caddy with Cloudflare and jakehillion DNS providers";
    mainProgram = "caddy";
  };
}
