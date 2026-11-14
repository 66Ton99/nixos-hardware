{ lib
, rustPlatform
, callPackage
, fetchFromGitHub
, kaiT2enSrc ? fetchFromGitHub {
    owner = "66Ton99";
    repo = "KaiT2en-Fedora";
    rev = "9b5672149b59ab9400ee8039d14208543d70c65f";
    hash = "sha256-KO+UBw7V/r/jYSAhTfTz3z37Igy5kN9Q49/UAR2Kzkw=";
  }
, sksLockState ? callPackage ./sks-lock-state.nix { inherit kaiT2enSrc; }
}:

let
  filteredSrc = lib.cleanSourceWith {
    src = kaiT2enSrc;
    filter = path: type:
      let base = baseNameOf path; in
      !(type == "directory" && (base == "target" || base == "build" || base == ".git" || base == ".gemini"));
  };
in
rustPlatform.buildRustPackage rec {
  pname = "t2-touchid-unlock";
  version = "0.1.0";

  src = filteredSrc;
  sourceRoot = "source/t2-services/t2-touchid/unlock";

  cargoLock = {
    lockFile = kaiT2enSrc + "/t2-services/t2-touchid/unlock/Cargo.lock";
  };

  postInstall = ''
    mkdir -p $out/libexec/kait2en
    cp $out/bin/t2-keybag-unlock $out/libexec/kait2en/
    cp $out/bin/t2-touchid-link-ready $out/libexec/kait2en/

    cp ${sksLockState}/bin/sks-lock-state $out/bin/
    cp ${sksLockState}/bin/sks-lock-state $out/libexec/kait2en/

    install -D -m 0755 $src/t2-services/t2-touchid/unlock/scripts/prepare-kernel-module.sh \
      $out/libexec/kait2en/prepare-kernel-module.sh
  '';

  meta = with lib; {
    description = "Manual Touch ID and Apple T2 SEP keybag unlock utility";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
