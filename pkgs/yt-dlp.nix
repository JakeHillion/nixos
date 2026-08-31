# YouTube gates downloads behind clients that yt-dlp 2026.07.04 cannot use,
# so every download fails with HTTP 403. 2026.08.19 restores extraction via
# the visionos client. Drop this override once nixpkgs carries that version;
# the assertion below fails the build when it does.
{ lib
, fetchFromGitHub
, yt-dlp
}:

let
  version = "2026.08.19";
in
assert lib.assertMsg (lib.versionOlder yt-dlp.version version)
  "pkgs/yt-dlp.nix: nixpkgs now has yt-dlp ${yt-dlp.version}, which is at least the pinned ${version}. Delete pkgs/yt-dlp.nix and its overlay entry in flake.nix.";

yt-dlp.overridePythonAttrs (_: {
  inherit version;

  src = fetchFromGitHub {
    owner = "yt-dlp";
    repo = "yt-dlp";
    tag = version;
    hash = "sha256-BM5ZeGTmHq+1xH6G/zsuCtjLgYgfRA11ya0zIHK5p4g=";
  };
})
