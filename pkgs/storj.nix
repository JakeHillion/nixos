{ stdenv, lib, fetchFromGitea, buildGoModule, ... }:

let
  version = "1.84.2";
  src = fetchFromGitea {
    domain = "gitea.hillion.co.uk";
    owner = "JakeHillion";
    repo = "storj";
    rev = "5546e07191f01be3269d5ea2dbf5ebb908852288";
    hash = "sha256-OpLxi84oS2sCUaZEuKTvbaygkxkRiXlAlRVQDV8VWHg=";
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
  vendorHash = "sha256-eSm1Bp+nycd1W9Tx5hvh/Ta3w9u1zsXZ4D77zAnViOA=";
  subPackages = [
    "cmd/storagenode"
    "cmd/identity"
  ];
}
