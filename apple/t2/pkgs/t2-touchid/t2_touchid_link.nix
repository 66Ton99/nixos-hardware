{ stdenv
, lib
, kernel
, openssl
, fetchFromGitHub
, kaiT2enSrc ? fetchFromGitHub {
    owner = "66Ton99";
    repo = "KaiT2en-Fedora";
    rev = "172ba3c60c724df336914aff135c590d95d37849";
    hash = "sha256-qHmieZTG2NhL4m1Knxp/Y2EOG3V5p8kr4FXzgEF+gkg=";
  }
}:

let
  filteredSrc = lib.cleanSourceWith {
    src = kaiT2enSrc;
    filter = path: type:
      let base = baseNameOf path; in
      !(type == "directory" && (base == "target" || base == "build" || base == ".git" || base == ".gemini"));
  };
in
stdenv.mkDerivation {
  pname = "t2_touchid_link";
  version = "0.1.0";

  src = filteredSrc;

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ openssl ];

  dontStrip = true;
  hardeningDisable = [ "pic" ];

  buildPhase = ''
    runHook preBuild

    cd modules/t2_touchid_link
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$(pwd) modules

    SIGN_FILE_C="${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/scripts/sign-file.c"
    if [ ! -f "$SIGN_FILE_C" ]; then
      SIGN_FILE_C="${kernel.dev}/lib/modules/${kernel.modDirVersion}/build/scripts/sign-file.c"
    fi

    if [ -f "$SIGN_FILE_C" ]; then
      $CC -O2 "$SIGN_FILE_C" -lcrypto -o sign-file
      openssl req -new -nodes -utf8 -sha256 -days 3650 -batch -x509 \
        -subj "/CN=T2 Linux/" \
        -out cert.pem -keyout key.pem
      ./sign-file sha256 key.pem cert.pem t2_touchid_link.ko
    fi

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -D -m 0644 t2_touchid_link.ko $out/lib/modules/${kernel.modDirVersion}/extra/t2_touchid_link.ko

    runHook postInstall
  '';

  meta = with lib; {
    description = "Apple T2 CDC-NCM carrier notification quirk module";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
  };
}
