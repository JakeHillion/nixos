{ lib, buildGoModule }:

let
  # Extract caddy version from go.mod to avoid maintaining it in two places
  goMod = builtins.readFile ./go.mod;
  version =
    let
      match = builtins.match ".*github.com/caddyserver/caddy/v2 v([^\n]+)\n.*" goMod;
    in
    builtins.head match;
in
buildGoModule {
  pname = "caddy-with-dns";
  inherit version;
  src = ./.;
  vendorHash = "sha256-1x9OrZAbJXaps4USw9s94NdEeWq0XvWNHkdMO7wLU1M=";
  subPackages = [ "." ];

  meta = {
    description = "Caddy with Cloudflare DNS and jakehillion DNS plugins";
    mainProgram = "caddy";
  };
}
