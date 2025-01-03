{ stdenv, lib, fetchFromGitHub, buildGoModule, buildNpmPackage, ... }:

let
  version = "v1.119.12";

  src = fetchFromGitHub {
    owner = "storj";
    repo = "storj";
    rev = version;
    hash = "sha256-wsUtJzogq5wIjO9/aKmK8QFUNYELliWr3Hck/acfhCY=";
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

  web = buildNpmPackage {
    pname = "storagenode-web";
    inherit version meta;
    src = "${src}/web/storagenode";

    npmDepsHash = "sha256-ZQetBPtt3S6T2+2w4YFDct2HgtMhQLu+N3O1ScyHMrM=";
    makeCacheWritable = true;
  };
in
buildGoModule rec {
  pname = "storagenode";
  inherit version src meta;
  vendorHash = "sha256-eYFdoc5gtY7u9LFT7EAnooxrOC1y9fIA0ESTP+rPpCc=";
  subPackages = [
    "cmd/storagenode"
    "cmd/identity"
  ];

  preFixup = ''
    cp -r ${web} web/storagenode/dist
  '';
}
