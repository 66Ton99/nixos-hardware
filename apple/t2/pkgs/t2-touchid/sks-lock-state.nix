{ lib
, rustPlatform
, fetchFromGitHub
, kaiT2enSrc ? fetchFromGitHub {
    owner = "66Ton99";
    repo = "KaiT2en-Fedora";
    rev = "23e66bacc724b6c2249b6fac4d7481515a961648";
    hash = "sha256-sMyP6DFbbMDejodN0Xu2NKug4M5qqbNE5WibSx87uHo=";
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
rustPlatform.buildRustPackage rec {
  pname = "sks-lock-state";
  version = "0.1.0";

  src = filteredSrc;
  sourceRoot = "source/t2-services/t2-touchid/protocols/t2-biometrickit";

  cargoLock = {
    lockFile = kaiT2enSrc + "/t2-services/t2-touchid/protocols/t2-biometrickit/Cargo.lock";
  };

  cargoBuildFlags = [ "--example" "sks-lock-state" ];

  installPhase = ''
    runHook preInstall
    install -D -m 0755 target/*/release/examples/sks-lock-state $out/bin/sks-lock-state
    runHook postInstall
  '';

  meta = with lib; {
    description = "Inspect Apple T2 Secure Key Store lock state over BridgeXPC";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
