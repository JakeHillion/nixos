{ stdenv, lib, fetchFromGitea, buildGoModule, ... }:

let
  version = "1.84.2";
  src = fetchFromGitea {
    domain = "gitea.hillion.co.uk";
    owner = "JakeHillion";
    repo = "storj";
    rev = "977a27dde2affe6801840b827dde387551b15126";
    hash = "sha256-DHDVrYGWGK91uMMa9rF3RVpFA9IVhtvqHJtLUXyuL5E=";
  };
  meta = with lib; {
    description = "Storj is building a distributed cloud storage network.";
    homepage = "https://github.com/storj/storj";
    license = licenses.agpl3Only;
    maintainers = [{
      email = "jake@hillion.co.uk";
      matrix = "@jake:hillion.co.uk";
      name = "Jake Hillion";
      github = "JakeHillion";
      githubId = 5712856;
    }];
  };
in
buildGoModule rec {
  pname = "storagenode";
  inherit version src meta;
  vendorHash = "sha256-iZEEADI1JxdsL1j4kJpkV3owfO8DnUcCNSKJMyPgYhE=";
  subPackages = [
    "cmd/storagenode"
    "cmd/identity"
  ];
}
