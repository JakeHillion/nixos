{ lib, stdenv, fetchFromGitHub, rustPlatform, pkg-config, perl, openssl, makeWrapper, gnused }:

rustPlatform.buildRustPackage rec {
  pname = "pbcli";
  version = "2.8.0";

  src = fetchFromGitHub {
    owner = "Mydayyy";
    repo = "pbcli";
    rev = "v${version}";
    hash = "sha256-JusJ1ovhETW5caTW2suNvKpw5Rl+CeecmCPCFRIi7N0=";
  };

  cargoHash = "sha256-MYPDKpExCRI+wJnaGP/rUmIEF1Q4dxxcHtiPZ8syXdc=";

  nativeBuildInputs = [ pkg-config perl ];
  buildInputs = [ openssl ];

  meta = with lib; {
    description = "Command-line client for PrivateBin";
    homepage = "https://github.com/Mydayyy/pbcli";
    license = with licenses; [ mit unlicense ];
    maintainers = [{
      email = "jake@hillion.co.uk";
      name = "Jake Hillion";
      github = "JakeHillion";
    }];
    mainProgram = "pbcli";
  };
}
