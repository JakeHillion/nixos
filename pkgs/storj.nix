{ stdenv, lib, fetchFromGitHub, buildGoModule, ... }:

let
  version = "1.80.9";
  src = fetchFromGitHub {
    owner = "storj";
    repo = "storj";
    rev = "v${version}";
    hash = "sha256-2YeBAwBpoMBRmIpNo7Vh81rtBKxJHyz817Fq0jsf1yc=";
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
  vendorHash = "sha256-Sz/aM1mYpYnnVc6PTfldaiHQPT8TZCPfB6vQpzM2GDo=";
  subPackages = [
    "cmd/storagenode"
    "cmd/identity"
  ];
}
