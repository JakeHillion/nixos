{ stdenv, lib, fetchFromGitHub, buildPythonPackage, ... }:

let
  version = "0.17.1";
  src = fetchFromGitHub {
    owner = "inventree";
    repo = "InvenTree";
    rev = version;
    hash = "";
  };
in
buildPythonPackage rec {
  pname = "inventree";
  inherit version src;

  meta = with lib; {
    description = "InvenTree is an open-source Inventory Management System which provides powerful low-level stock control and part tracking.";
    homepage = "https://inventree.org/";
    license = licenses.MIT;
    maintainers = [{
      email = "jake@hillion.co.uk";
      matrix = "@jake:hillion.co.uk";
      name = "Jake Hillion";
      github = "JakeHillion";
      githubId = 5712856;
    }];
  };
}
