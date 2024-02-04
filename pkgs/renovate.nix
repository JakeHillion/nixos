{ lib, buildNpmPackage, fetchFromGitHub, ... }:

buildNpmPackage rec {
  pname = "renovate";
  version = "37.171.2";

  src = fetchFromGitHub {
    owner = "renovatebot";
    repo = pname;
    rev = version;
    hash = "";
  };

  npmDepsHash = "";

  meta = with lib; {
    description = "Universal dependency automation tool.";
    homepage = "https://github.com/renovatebot/renovate";
    license = licenses.agpl3Only;
    maintainers = [{
      email = "jake@hillion.co.uk";
      matrix = "@jake:hillion.co.uk";
      name = "jake hillion";
      github = "jakehillion";
      githubid = 5712856;
    }];
  };
}
