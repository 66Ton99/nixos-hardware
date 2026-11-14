# NixOS on T2 Macs

This is the `nixos-hardware` module of the [T2 Linux Project](https://t2linux.org).

Overall, most features (WiFi, bluetooth, audio, touchbar, ...) of Macs are supported, [see this page](https://wiki.t2linux.org/state/) for a detailed list of things that work and things that don't/partially work.

Following [this guide](https://wiki.t2linux.org/distributions/nixos/installation/) is the recommended way to install, as it incudes the extra things you have to do on a T2 Mac.

You can consult the [wiki](https://wiki.t2linux.org/) for information specific to T2 Macs.

## Touch ID & Biometric Authentication

To enable Touch ID biometric authentication using the `KaiT2en` bridge:

```nix
hardware.apple-t2.touchId = {
  enable = true;
  # Automatically bind macOS-enrolled fingerprints to this Linux user:
  bindUser = "yourusername";
  # macOS user ID whose enrolled fingers to verify against (default: "auto" or 501):
  macosUid = "auto";
  # Enable guarded manual SEP keybag unlock utility (t2-touchid-unlock):
  enableManualUnlock = true; # default: true
};

# Enable fingerprint authentication in PAM:
security.pam.services.sudo.fprintAuth = true;
```

### Manual SEP Unlock Utility

When `enableManualUnlock` is active, `t2-touchid-unlock`, `t2-keybag-unlock`, `sks-lock-state`, and the signed `t2sep.ko` module are prepared automatically.

- Read-only verification check:
  ```bash
  sudo t2-touchid-unlock --check-only
  ```
- Guided manual unlock:
  ```bash
  sudo t2-touchid-unlock --accept-risk
  ```

## Kernel Channels

- `hardware.apple-t2.kernelChannel = "stable"` (default): Linux 6.18 with the updated `t2bce` driver stack and Broadcom Wi-Fi IPv6 ND fixes.
- `hardware.apple-t2.kernelChannel = "latest"`: Linux 7.3 with the latest `t2bce` and `macsmc` driver stacks.

> [!warning]
> Always ensure compatibility and make backups of your data before making any system changes.
