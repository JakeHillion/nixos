{ stdenv, lib, fetchFromGitea, buildGoModule, ... }:

let
  version = "1.82.1";
  src = fetchFromGitea {
    domain = "gitea.hillion.co.uk";
    owner = "JakeHillion";
    repo = "storj";
    rev = "f75ec5ba34b2ccce005ebdb6fae697e0224998d9";
    hash = "sha256-zUpzkdiAbE10fq1KDXEarPURqByD8JV0NkQ9iNxPlWI=";
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
  vendorHash = "sha256-Q9+uwFmPrffvQGT9dHxf0ilCcDeVhUxrJETsngwZUXA=";
  subPackages = [
    "cmd/storagenode"
    "cmd/identity"
  ];
}
