{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, gzip
}:

stdenv.mkDerivation rec {
  pname = "firectl";
  version = "stable";

  src = fetchurl {
    url = "https://storage.googleapis.com/fireworks-public/firectl/stable/linux-amd64.gz";
    hash = "sha256-sYBmrPi5WhX/1zcXuu7v+tftB1n7ESsNIH/se3TXDm8=";
  };

  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
    gzip
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    gunzip -c $src > $out/bin/firectl
    chmod +x $out/bin/firectl
    runHook postInstall
  '';

  meta = {
    description = "Command-line interface for Fireworks.AI";
    homepage = "https://docs.fireworks.ai/tools-sdks/firectl/firectl";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "firectl";
  };
}
