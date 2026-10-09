# WireGuard Apple integration

This directory contains the WireGuardKit, WireGuardKitC, and WireGuardKitGo sources from the official WireGuard Apple repository:

- Upstream: https://git.zx2c4.com/wireguard-apple (GitHub mirror: https://github.com/WireGuard/wireguard-apple)
- Imported revision: `2fec12a6e1f6e3460b6ee483aa00ad29cddadab1`
- License: MIT; see `COPYING`.

LiteVPN adapts the package manifest to Swift tools 5.5 so Xcode can resolve the `.macOS(.v12)` platform declaration. `WireGuardKitC.h` uses the SDK's `<sys/kern_control.h>` definitions to avoid duplicate structure declarations with current SDK modules. `WireGuardAdapter.swift` defines the Darwin control ioctl value directly because the SDK header macro is not imported into Swift by current Xcode.

The app and system extension share one Network Extension manager and one packet tunnel provider. OpenVPN continues through TunnelKit; WireGuard uses the official `WireGuardAdapter`. The `.conf` parser is kept in `Shared/` and is used at import and tunnel startup. Xcode's system-extension pre-build phase builds the Go bridge for arm64 and x86_64 into DerivedData.
