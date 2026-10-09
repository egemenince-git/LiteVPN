# LiteVPN

**English** | [简体中文](README.zh-CN.md) | [Türkçe](README.tr.md)

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-green.svg)
![Swift](https://img.shields.io/badge/Swift-5-orange.svg)
![License GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-lightgray.svg)

A minimal, lightweight **OpenVPN menu bar client for macOS** — built as an alternative to the bulky OpenVPN Connect. Instant to open, light on memory, with no account system, no push notifications, and no update popups.

100% Swift, powered by [TunnelKit](https://github.com/partout-io/tunnelkit) — the pure-Swift OpenVPN protocol implementation that drives the open-source client Passepartout.

<p align="center"><img src="docs/screenshot.png" width="560" alt="LiteVPN — OpenVPN menu bar client for macOS (connected state)"></p>

## Features

- **Lives in the menu bar** (no Dock icon), one-click connect / disconnect
- **.ovpn import**: drag & drop onto the panel or use the file picker, validated at import time, multiple profiles
- **Vitals-inspired live status**: connection duration, live download / upload rates, cumulative traffic, traffic graph, and public IP
- **Multiple profiles**: import, select, rename, and delete `.ovpn` profiles; profile names are sorted alphabetically
- **Auto-reconnect** on drops (built into TunnelKit), optional **Launch at Login**
- Tunnel runs as a macOS Network Extension system extension — quitting the menu bar app does not remove the VPN service
- Localized UI: English & 简体中文 (follows system language)
- Dark, translucent menu bar interface

Deliberately minimal: only certificate-embedded profiles (inline `<ca>` / `<cert>` / `<key>`) are supported. No username/password authentication.

## Architecture

```
┌─────────────────────────┐      ┌──────────────────────────────┐
│ LiteVPN.app (menu bar)  │      │ LiteVPNTunnel.systemextension│
│ SwiftUI MenuBarExtra    │─────▶│ NEPacketTunnelProvider       │
│ SystemExtensionInstaller│ NE   │ └─ TunnelKit OpenVPN engine  │
│ profiles/status/traffic │◀─────│    (protocol + data channel) │
└─────────────────────────┘ AppGroup └──────────────────────────┘
```

- The protocol engine surface is kept deliberately small (tunnel subclass + parser + connection manager), leaving room for a future WireGuard engine
- TunnelKit v6.3.2 is vendored at `Vendor/tunnelkit/` with WireGuard stripped (upstream is archived and its wireguard-apple dependency repo was deleted, so remote references are no longer reliable) — see [Vendor/tunnelkit/LITEVPN-MODIFICATIONS.md](Vendor/tunnelkit/LITEVPN-MODIFICATIONS.md)
- The crypto layer is pinned to the OpenSSL **3.5 LTS** line (supported until April 2030) via `.upToNextMinor`, so dependency resolution only picks up 3.5.x patch releases and never drifts onto a short-lived release line

## Build and direct distribution

Requirements: macOS 26 or later, Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), and an Apple Developer Program membership.

Generate and build locally:

```bash
xcodegen generate
xcodebuild -project LiteVPN.xcodeproj -scheme LiteVPN \
  -derivedDataPath Build -allowProvisioningUpdates build
```

For downloads outside the Mac App Store, sign with a **Developer ID Application** certificate and notarize the app. In Certificates, Identifiers & Profiles, enable the Network Extension capability for the app IDs (`com.egemenince.LiteVPN` and `com.egemenince.LiteVPN.Tunnel`) and create the matching Developer ID provisioning profiles. The system extension bundle is named after its bundle identifier (`com.egemenince.LiteVPN.Tunnel.systemextension`); the release script validates the embedded name and identifier before notarization. The project uses the system-extension Network Extension entitlement and hardened runtime.

Save a `notarytool` Keychain profile named `LiteVPN-Notary`, then provide the two profile names and run:

```bash
xcodegen generate
LITEVPN_APP_PROFILE="<app Developer ID profile name>" \
LITEVPN_TUNNEL_PROFILE="<system extension Developer ID profile name>" \
Scripts/release-direct.sh
```

The script archives, signs, submits for notarization, staples the ticket, and writes a ZIP under `Build/DirectDistribution/`. On first launch, macOS may ask the user to approve LiteVPN in System Settings before its VPN system extension can activate.

## Usage

1. Click the shield icon in the menu bar
2. Drag in your `.ovpn` file (or click "+ Import")
3. Hit **Connect**

For a Turkish walkthrough, see [README.tr.md](README.tr.md).

## Credits

- [TunnelKit](https://github.com/partout-io/tunnelkit) by Davide De Rosa — OpenVPN protocol engine
- [OpenSSL](https://github.com/partout-io/openssl-apple) — crypto layer (3.5 LTS)

## License

[GPL-3.0](LICENSE) (inherited from the TunnelKit engine).

## Author

云中江树 (yzfly) · WeChat Official Account: 云中江树

This personal fork is maintained by Egemen Ince and keeps the upstream project's GPL-3.0 license and attribution.
