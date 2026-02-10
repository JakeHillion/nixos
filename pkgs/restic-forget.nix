{ lib, stdenv, python3, makeWrapper }:

let
  python = python3.withPackages (ps: [ ps.pytest ]);
in
stdenv.mkDerivation {
  pname = "restic-forget";
  version = "0.1.0";

  src = ./restic-forget;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python ];

  doCheck = true;
  checkPhase = ''
    ${python}/bin/python -m pytest test_restic_forget.py -v
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp restic_forget.py $out/bin/restic-forget
    chmod +x $out/bin/restic-forget
    wrapProgram $out/bin/restic-forget \
      --prefix PATH : ${python}/bin
  '';

  meta = {
    description = "Restic forget with time-based and size-based retention";
    license = lib.licenses.mit;
    mainProgram = "restic-forget";
  };
}
