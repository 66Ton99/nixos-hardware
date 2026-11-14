{ stdenv
, lib
, kernel
, openssl
, fetchFromGitHub
, kaiT2enSrc ? fetchFromGitHub {
    owner = "66Ton99";
    repo = "KaiT2en-Fedora";
    rev = "9b5672149b59ab9400ee8039d14208543d70c65f";
    hash = "sha256-KO+UBw7V/r/jYSAhTfTz3z37Igy5kN9Q49/UAR2Kzkw=";
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
  pname = "t2sep";
  version = "0.1.0";

  src = filteredSrc;

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ openssl ];

  dontStrip = true;
  hardeningDisable = [ "pic" ];

  buildPhase = ''
    runHook preBuild

    cd modules/t2sep
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
      ./sign-file sha256 key.pem cert.pem t2sep.ko
    fi

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
    cp t2sep.ko $out/lib/modules/${kernel.modDirVersion}/extra/

    mkdir -p $out/libexec/t2sep
    cp t2sep.ko $out/libexec/t2sep/

    runHook postInstall
  '';

  meta = with lib; {
    description = "Apple T2 Secure Enclave Processor transport kernel module";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
