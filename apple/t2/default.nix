{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) types;

  audioFiles = pkgs.fetchFromGitHub {
    owner = "kekrby";
    repo = "t2-better-audio";
    rev = "e46839a28963e2f7d364020518b9dac98236bcae";
    hash = "sha256-x7K0qa++P1e1vuCGxnsFxL1d9+nwMtZUJ6Kd9e27TFs=";
  };

  audioFilesUdevRules = pkgs.runCommand "audio-files-udev-rules" { } ''
    mkdir -p $out/lib/udev/rules.d
    cp ${audioFiles}/files/*.rules $out/lib/udev/rules.d
    substituteInPlace $out/lib/udev/rules.d/*.rules --replace "/usr/bin/sed" "${pkgs.gnused}/bin/sed"
  '';

  overrideAudioFiles =
    package: pluginsPath:
    package.overrideAttrs (
      _new: old: {
        preConfigurePhases = old.preConfigurePhases or [ ] ++ [ "postPatchPhase" ];
        postPatchPhase = ''
          cp -r ${audioFiles}/files/{profile-sets,paths} ${pluginsPath}/alsa/mixer/
        '';
      }
    );

  pipewirePackage = overrideAudioFiles pkgs.pipewire "spa/plugins/";

  t2Cfg = config.hardware.apple-t2;

in
{
  imports = [
    (lib.mkRemovedOptionModule [ "hardware" "apple-t2" "enableTinyDfr" ] ''
      The hardware.apple-t2.enableTinyDfr option was deprecated and removed since upstream Nixpkgs now has an identical module.
      Please migrate to hardware.apple.touchBar.
    '')

    (lib.mkRemovedOptionModule [ "hardware" "apple-t2" "enableAppleSetOsLoader" ] ''
      The hardware.apple-t2.enableAppleSetOsLoader option was removed as the apple_set_os functionality was integrated into the kernel.
      Please uninstall the loader by replacing /esp/EFI/BOOTX64.EFI with /esp/EFI/BOOTX64_original.EFI, where esp is the EFI partition mount point.

      If you have a device with an AMD dGPU and would like to keep using the iGPU, please set hardware.apple-t2.enableIGPU to true.
    '')
  ];
  options.hardware.apple-t2 = {
    enableIGPU = lib.mkEnableOption "the usage of the iGPU on specific Apple devices with an AMD dGPU";
    kernelChannel = lib.mkOption {
      type = types.enum [
        "stable"
        "latest"
      ];
      default = "stable";
      example = "latest";
      description = "The kernel release stream to use.";
    };
    firmware = {
      enable = lib.mkEnableOption "automatic and declarative Wi-Fi and Bluetooth firmware configuration";
      version = lib.mkOption {
        type = types.enum [
          "monterey"
          "ventura"
          "sonoma"
        ];
        default = "sonoma";
        example = "ventura";
        description = "The macOS version to use.";
      };
    };
    touchId = {
      enable = lib.mkEnableOption "Touch ID biometric daemon and fprintd integration for Apple T2 Macs";

      src = lib.mkOption {
        type = types.path;
        default = pkgs.fetchFromGitHub {
          owner = "66Ton99";
          repo = "KaiT2en-Fedora";
          rev = "b906a2d30e7f0f58fee7dd5d9d09f822b6b85fb3";
          hash = "sha256-q1pzClRG7PEB9Kq4pK/bxfgG5N9+MXqSsq0qKD229QI=";
        };
        description = "Source repository providing KaiT2en Touch ID services and drivers.";
      };

      bindUser = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "ton";
        description = "Linux user account to bind macOS-enrolled fingerprints to automatically.";
      };

      macosUid = lib.mkOption {
        type = types.either types.ints.u32 (types.enum [ "auto" ]);
        default = "auto";
        example = 501;
        description = "The macOS user ID whose enrolled fingers this machine verifies against ('auto' or numeric ID).";
      };

      enableManualUnlock = lib.mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to install the guarded manual Touch ID/SEP keybag unlock utility (t2-touchid-unlock)
          and prepare its signed t2sep module assets.
        '';
      };
    };
  };

  config = lib.mkMerge [
    {
      # Specialized kernel for keyboard, touchpad, touchbar and audio.
      boot.kernelPackages = pkgs.linuxPackagesFor (
        pkgs.callPackage (
          if t2Cfg.kernelChannel == "stable" then ./pkgs/linux-t2 else ./pkgs/linux-t2/latest.nix
        ) { }
      );
      boot.initrd.kernelModules = [
        "t2bce_core"
        "t2bce_vhci"
      ];
      boot.kernelModules = [
        "t2bce_audio"
      ];

      services.udev.packages = [ audioFilesUdevRules ];

      # For audio and suspend
      boot.kernelParams = [
        "intel_iommu=on"
        "iommu=pt"
        "pm_async=off"
      ];

      services.pipewire.package = pipewirePackage;
      services.pipewire.wireplumber.package = pkgs.wireplumber.override {
        pipewire = pipewirePackage;
      };

      # Make sure post-resume.service exists
      powerManagement.enable = true;
    }

    {
      services.pulseaudio.package = overrideAudioFiles pkgs.pulseaudio "src/modules/";
    }

    (lib.mkIf t2Cfg.enableIGPU {
      # Enable the iGPU by default if present
      environment.etc."modprobe.d/apple-gmux.conf".text = ''
        options apple-gmux force_igd=y
      '';
    })
    (lib.mkIf t2Cfg.firmware.enable {
      # Configure Wi-Fi and Bluetooth firmware
      hardware.firmware = [
        (pkgs.callPackage ./pkgs/brcm-firmware { version = t2Cfg.firmware.version; })
      ];
    })
    (lib.mkIf t2Cfg.touchId.enable (
      let
        t2TouchIdPkg = pkgs.callPackage ./pkgs/t2-touchid { kaiT2enSrc = t2Cfg.touchId.src; };
        t2TouchIdUnlockPkg = pkgs.callPackage ./pkgs/t2-touchid/unlock.nix { kaiT2enSrc = t2Cfg.touchId.src; };
        t2sepPkg = pkgs.callPackage ./pkgs/t2-touchid/t2sep.nix {
          kernel = config.boot.kernelPackages.kernel;
          kaiT2enSrc = t2Cfg.touchId.src;
        };
      in
      {
        services.fprintd.enable = true;

        systemd.services.fprintd = {
          requires = [ "kait2en-t2-touchid.service" ];
          after = [ "kait2en-t2-touchid.service" ];
          environment.FP_VIRTUAL_DEVICE_STORAGE = "/run/t2-touchid/fprint.sock";
          serviceConfig = {
            RuntimeDirectory = "t2-touchid";
            RuntimeDirectoryMode = "0700";
            RuntimeDirectoryPreserve = "yes";
            ReadWritePaths = [ "/run/t2-touchid" ];
          };
        };

        systemd.services.kait2en-t2-touchid = {
          description = "KaiT2en Touch ID bridge for fprintd";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" "kait2en-t2-link-ready.service" ];
          wants = [ "kait2en-t2-link-ready.service" ];
          path = [ pkgs.fprintd ];
          serviceConfig = {
            Type = "simple";
            EnvironmentFile = "/etc/kait2en/t2-touchid.conf";
            ExecStart = "${t2TouchIdPkg}/bin/t2-touchid --socket \${T2_TOUCHID_SOCKET} --uid \${T2_TOUCHID_UID} --flags \${T2_TOUCHID_FLAGS} --bind-user \${T2_TOUCHID_BIND_USER}";
            Restart = "on-failure";
            RestartSec = "5";
            RuntimeDirectory = "t2-touchid";
            RuntimeDirectoryMode = "0700";
            RuntimeDirectoryPreserve = "yes";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
          };
        };

        systemd.services.kait2en-t2-link-ready = {
          description = "Prepare the internal Apple T2 CDC-NCM network link";
          wantedBy = [ "multi-user.target" ];
          after = [ "systemd-udev-trigger.service" ];
          before = [ "kait2en-t2-touchid.service" ];
          path = [ pkgs.iproute2 pkgs.kmod ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${t2TouchIdUnlockPkg}/bin/t2-touchid-link-ready";
            TimeoutStartSec = 60;
            RemainAfterExit = true;
          };
        };

        # CDC-NCM link-local network configuration for systemd-networkd
        environment.etc."systemd/network/99-t2-touchid.network".text = ''
          [Match]
          MACAddress=ac:de:48:00:11:22

          [Network]
          LinkLocalAddressing=ipv6
          LLMNR=no
          MulticastDNS=no
        '';

        environment.etc."kait2en/t2-touchid.conf".text = ''
          T2_TOUCHID_UID=${toString t2Cfg.touchId.macosUid}
          T2_TOUCHID_FLAGS=0
          T2_TOUCHID_BIND_USER=${if t2Cfg.touchId.bindUser != null then t2Cfg.touchId.bindUser else "none"}
          T2_TOUCHID_SOCKET=/run/t2-touchid/fprint.sock
        '';

        services.dbus.packages = [ t2TouchIdPkg ];
        environment.systemPackages = [ t2TouchIdPkg ]
          ++ lib.optional t2Cfg.touchId.enableManualUnlock t2TouchIdUnlockPkg;

        system.activationScripts = lib.mkIf t2Cfg.touchId.enableManualUnlock {
          kait2enTouchIdUnlock = {
            supportsDryActivation = true;
            text = ''
              mkdir -p /etc/kait2en
              chmod 0755 /etc/kait2en

              cat << 'EOF' > /etc/kait2en/touchid-unlock.json.tmp
              {
                "macos_uid": ${if t2Cfg.touchId.macosUid == "auto" then "501" else toString t2Cfg.touchId.macosUid}
              }
              EOF
              chmod 0600 /etc/kait2en/touchid-unlock.json.tmp
              mv -f /etc/kait2en/touchid-unlock.json.tmp /etc/kait2en/touchid-unlock.json

              mkdir -p /var/lib/kait2en/touchid-unlock/assets
              kver="${config.boot.kernelPackages.kernel.modDirVersion}"
              mkdir -p "/var/lib/kait2en/touchid-unlock/assets/$kver"
              chmod 0700 /var/lib/kait2en/touchid-unlock
              chmod 0755 /var/lib/kait2en/touchid-unlock/assets
              chmod 0755 "/var/lib/kait2en/touchid-unlock/assets/$kver"
              mkdir -p /var/lib/kait2en/touchid-unlock/reports
              chmod 0700 /var/lib/kait2en/touchid-unlock/reports

              for dir in /var/lib/kait2en/touchid-unlock/assets "/var/lib/kait2en/touchid-unlock/assets/$kver"; do
                cp -f ${t2sepPkg}/libexec/t2sep/t2sep.ko "$dir/t2sep.ko"
                chmod 0644 "$dir/t2sep.ko"

                cp -f ${t2TouchIdUnlockPkg}/libexec/kait2en/t2-keybag-unlock "$dir/t2-keybag-unlock"
                chmod 0700 "$dir/t2-keybag-unlock"

                cp -f ${t2TouchIdUnlockPkg}/libexec/kait2en/sks-lock-state "$dir/sks-lock-state"
                chmod 0700 "$dir/sks-lock-state"

                cp -f ${t2TouchIdUnlockPkg}/libexec/kait2en/prepare-kernel-module.sh "$dir/prepare-kernel-module.sh"
                chmod 0755 "$dir/prepare-kernel-module.sh"
              done

              if [ -f /mnt/oracle/var/lib/kait2en/touchid-unlock/user.kb ] && [ ! -f /var/lib/kait2en/touchid-unlock/user.kb ]; then
                cp -f /mnt/oracle/var/lib/kait2en/touchid-unlock/user.kb /var/lib/kait2en/touchid-unlock/user.kb
                chmod 0600 /var/lib/kait2en/touchid-unlock/user.kb
              fi
            '';
          };
        };
      }
    ))
  ];
}
