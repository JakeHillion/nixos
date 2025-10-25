{ lib
, python3
, qnaplcd-menu
}:

python3.pkgs.buildPythonPackage {
  pname = "qnaplcd";
  version = "unstable-2024-01-01";

  src = qnaplcd-menu;

  # Use a simple format since there's no setup.py
  format = "other";

  propagatedBuildInputs = with python3.pkgs; [
    pyserial
  ];

  # Install the qnaplcd module directly
  installPhase = ''
    mkdir -p $out/${python3.sitePackages}
    cp -r qnaplcd $out/${python3.sitePackages}/
  '';

  # No tests in the repository
  doCheck = false;

  meta = with lib; {
    description = "Python package for controlling QNAP front panel LCD displays";
    homepage = "https://github.com/stephenhouser/QnapLCD-Menu";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
