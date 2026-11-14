{ lib
, rustPlatform
, pkg-config
, makeWrapper
, fprintd
, udev
, libinput
, kaiT2enSrc ? /mnt/src/KaiT2en-Fedora
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
  pname = "t2-touchid";
  version = "0.1.0";

  src = filteredSrc;
  sourceRoot = "source/t2-services/t2-touchid";

  cargoLock = {
    lockFile = kaiT2enSrc + "/t2-services/t2-touchid/Cargo.lock";
  };

  nativeBuildInputs = [ pkg-config makeWrapper ];
  buildInputs = [ udev libinput ];

  postInstall = ''
    install -D -m 0644 $src/t2-services/t2-touchid/integration/dbus/org.kait2en.TouchId.conf \
      $out/share/dbus-1/system.d/org.kait2en.TouchId.conf

    install -D -m 0644 $src/t2-services/t2-touchid/integration/systemd/kait2en-t2-touchid.service \
      $out/lib/systemd/system/kait2en-t2-touchid.service
    substituteInPlace $out/lib/systemd/system/kait2en-t2-touchid.service \
      --replace-fail "@BINDIR@/t2-touchid" "$out/bin/t2-touchid"

    install -D -m 0644 $src/t2-services/t2-touchid/integration/systemd/kait2en-t2-link-ready.service \
      $out/lib/systemd/system/kait2en-t2-link-ready.service

    install -D -m 0644 $src/t2-services/t2-touchid/integration/fprintd/fprintd-kait2en-t2-touchid.conf \
      $out/lib/systemd/system/fprintd.service.d/fprintd-kait2en-t2-touchid.conf

    wrapProgram $out/bin/t2-touchid \
      --prefix PATH : ${lib.makeBinPath [ fprintd ]}
  '';

  meta = with lib; {
    description = "Touch ID daemon bridge for Apple T2 Macs";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
