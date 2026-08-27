# pi-web-access: web search + URL fetch tools for the Pi coding agent
# (https://github.com/nicobailon/pi-web-access). The upstream source is fetched
# by pinned GitHub ref (nothing vendored in this repo). The output is a
# self-contained extension dir (TypeScript sources + node_modules) that pi's
# loader picks up from the extensions linkFarm.
{ lib, buildNpmPackage, fetchFromGitHub, jq, stdenv }:
let
  upstreamSrc = fetchFromGitHub {
    owner = "nicobailon";
    repo = "pi-web-access";
    rev = "v0.25.0";
    sha256 = "sha256-Ad8H3vdY4zOivqqWhQd+FWhL0DGtFtGG4TY+w7eCFqk=";
  };

  # The upstream package-lock.json carries peer-installed @earendil-works/pi-*
  # entries (npm>7 auto-installs peers) that lack an `integrity` field and
  # break both importNpmLock and fetchNpmDeps. pi provides those modules at
  # runtime, so prune them from the lock in a pure derivation before the
  # dependency tree is fetched.
  prunedSrc = stdenv.mkDerivation {
    pname = "pi-web-access-src";
    version = "0.25.0";
    src = upstreamSrc;
    nativeBuildInputs = [ jq ];
    buildPhase = ''
      jq '.packages |= with_entries(select(.key | startswith("node_modules/@earendil-works/") | not))' \
        package-lock.json > package-lock.json.tmp
      mv package-lock.json.tmp package-lock.json
    '';
    installPhase = ''
      mkdir -p "$out"
      cp -r . "$out/"
    '';
  };
in
buildNpmPackage {
  pname = "pi-web-access";
  version = "0.25.0";

  src = prunedSrc;

  # Dependency tree hash for the pruned lockfile, obtained by building once
  # with a placeholder npmDepsHash.
  npmDepsHash = "sha256-/uXviy9kKBVqwc9VwCPUNRgmbNw+iJL9F3Pa7GQmz0Q=";

  # Peer deps (@earendil-works/pi-*) are provided by the pi runtime and were
  # pruned from the lockfile, so skip npm's peer auto-install.
  npmFlags = [ "--legacy-peer-deps" ];

  # TypeScript sources are consumed directly by pi's extension loader; there is
  # no compile step (running `npm run build` would fail — there is no build
  # script).
  dontNpmBuild = true;

  # The default buildNpmPackage install hook only ships the files listed by
  # `npm pack` (which excludes the raw .ts sources). Copy the full source tree
  # plus node_modules into the package output instead. `npm ci` already ran in
  # the configure phase, so node_modules is present in the build dir.
  installPhase = ''
    runHook preInstall
    pkgOut="$out/lib/node_modules/pi-web-access"
    mkdir -p "$pkgOut"
    cp -r "$src/." "$pkgOut/"
    cp -r node_modules "$pkgOut/"
    runHook postInstall
  '';

  meta = {
    description = "Web search, URL fetching, and content extraction tools for the Pi coding agent";
    homepage = "https://github.com/nicobailon/pi-web-access";
    license = lib.licenses.mit;
  };
}
