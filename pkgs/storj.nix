{ stdenv, lib, fetchFromGitHub, buildGoModule, ... }:

let
  version = "1.82.1";
  src = fetchFromGitHub {
    owner = "storj";
    repo = "storj";
    rev = "v${version}";
    hash = "sha256-DPWSQv4TKdOYfwsXokev42UfoxJLmC/OWLk48JnThUU=";
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
