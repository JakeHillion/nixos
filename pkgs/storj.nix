{ stdenv, lib, fetchFromGitea, buildGoModule, ... }:

let
  version = "1.84.2";
  src = fetchFromGitea {
    domain = "gitea.hillion.co.uk";
    owner = "JakeHillion";
    repo = "storj";
    rev = "540c9cb64738d8f1562b706807a9788361d5087e";
    hash = "sha256-gCrxbwqGfQeeFxkG96N1bTtME30nD74yhNMXVhujSfI=";
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
  vendorHash = "sha256-6BE3/jNCnPBUqSAhAE9p9kKJQRJyWetPBMwTYhMffpw=";
  subPackages = [
    "cmd/storagenode"
    "cmd/identity"
  ];
}
