{ lib, stdenvNoCC, fetchurl, unzip, skopeo }:

let
  source = builtins.fromJSON (builtins.readFile ./source.json);
  imageName = "unifi-os-server";
in
stdenvNoCC.mkDerivation {
  pname = "unifi-os-server-image";
  version = source.version;

  # Ubiquiti ships UniFi OS Server as an ELF installer with an OCI image
  # appended as a ZIP. This is the installer binary; the image is carved out
  # below.
  installer = fetchurl {
    url = source.url;
    sha256 = source.sha256;
  };

  dontUnpack = true;

  nativeBuildInputs = [ unzip skopeo ];

  buildPhase = ''
    runHook preBuild

    # The appended ZIP holds image.tar (the OCI image) alongside the
    # installer's own tooling. unzip warns about the ELF bytes preceding the
    # archive and exits non-zero despite succeeding.
    unzip -o "$installer" image.tar || true
    test -f image.tar
    # The ZIP stores no permission bits, so the extracted file lands mode 000.
    chmod u+rw image.tar

    # The image loads as "uosserver:<content-hash>", which changes every
    # release. Retag it to a stable version so the container can reference it
    # deterministically.
    HOME="$TMPDIR" skopeo --insecure-policy copy \
      docker-archive:image.tar \
      "docker-archive:image-tagged.tar:${imageName}:${source.version}"

    runHook postBuild
  '';

  # $out is the image archive itself so it can be used directly as an
  # oci-containers imageFile.
  installPhase = ''
    runHook preInstall
    cp image-tagged.tar "$out"
    runHook postInstall
  '';

  passthru = {
    inherit imageName;
    imageTag = "${imageName}:${source.version}";
  };

  meta = {
    description = "UniFi OS Server OCI image, carved from Ubiquiti's self-hosted installer";
    homepage = "https://ui.com/download/unifi-os-server";
    platforms = [ "x86_64-linux" ];
  };
}
