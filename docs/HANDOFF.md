# LiteVPN project handoff

## Project and current release

- Repository: `egemenince-git/LiteVPN`, a personal fork of `yzfly/LiteVPN`.
- `origin` points to the personal repository; `upstream` points to `yzfly/LiteVPN`.
- Current release: **1.1.5**, build **8**, tag `v1.1.5`.
- Release page: <https://github.com/egemenince-git/LiteVPN/releases/tag/v1.1.5>.
- The release ZIP is Developer ID signed, notarized by Apple, and stapled.
- The `feature/wireguard` branch contains validated source for **1.1.7**, build **10**. It is not tagged or published as a GitHub release.
- The public repository keeps the upstream GPL-3.0 license and attribution.

## Product behavior

LiteVPN is a macOS 26+ SwiftUI menu bar app for OpenVPN and WireGuard profiles. It imports inline-certificate `.ovpn` files and wg-quick `.conf`, `.wg`, and `.wgconf` files, lets the user select, alphabetically browse, rename, and delete profiles, and shows connection status, duration, public IP, live traffic rates, a traffic graph, and received/sent totals. Launch at Login is optional. OpenVPN username/password profiles and nonstandard WireGuard directives such as `PreUp` / `PostUp` are not supported.

The app UI is in `App/MenuView.swift`; VPN state, public-IP lookup, and traffic display state are managed in `App/VPNController.swift`. Profiles are managed by `App/ProfileStore.swift`. Do not inspect, print, or commit user profile data: `.ovpn` text can contain private keys.

## Architecture and identifiers

- `LiteVPN.app` is the menu bar UI and Network Extension manager.
- `LiteVPNTunnel.systemextension` is the shared packet tunnel. It subclasses TunnelKit's `OpenVPNTunnelProvider`: OpenVPN profiles use the superclass; WireGuard profiles use the official `WireGuardAdapter` from `Vendor/wireguard-apple/`.
- `Shared/TunnelConfiguration+WgQuickConfig.swift` is the official wg-quick parser adapted for app import validation and extension startup.
- `Tunnel/PacketTunnelProvider.swift` switches protocol based on the provider configuration. Keep the OpenVPN path intact when changing the WireGuard start/stop lifecycle.
- TunnelKit v6.3.2 is vendored under `Vendor/tunnelkit/`; WireGuard has been removed because the upstream dependency is archived. See `Vendor/tunnelkit/LITEVPN-MODIFICATIONS.md`.
- WireGuardKit and its Go backend are vendored under `Vendor/wireguard-apple/`; source revision and local adaptations are documented in `Vendor/wireguard-apple/LITEVPN-INTEGRATION.md`. The XcodeGen pre-build phase compiles a universal arm64/x86_64 `libwg-go.a` into DerivedData. A first build needs Go (1.17+) and network access to download Go modules. WireGuard Apple sources carry their MIT license in `Vendor/wireguard-apple/COPYING`.
- The app and extension share traffic/configuration data through the App Group.

Current signing and Network Extension values (change them together if transferring ownership):

| Setting | Value |
| --- | --- |
| Apple Team ID | `99U7KZC748` |
| App bundle ID | `com.egemenince.LiteVPN` |
| Tunnel bundle ID | `com.egemenince.LiteVPN.Tunnel` |
| App Group | `99U7KZC748.group.com.egemenince.LiteVPN` |
| Tunnel Mach service | `99U7KZC748.group.com.egemenince.LiteVPN.Tunnel` |

The Mach service must remain inside the App Group namespace. The extension must be embedded at `Contents/Library/SystemExtensions/com.egemenince.LiteVPN.Tunnel.systemextension`, use package type `SYSX`, and be declared as a system packet-tunnel provider. `Scripts/release-direct.sh` validates these requirements before notarization.

## Traffic counter behavior

The app first reads TunnelKit's `OpenVPN.DataCount` value from the shared App Group defaults. When that value is missing, `SystemTunnelTrafficCounter` in `App/VPNController.swift` reads byte counters from macOS `utun` interfaces and reports the session delta. Rates are calculated from successive byte-count samples. Counts and rates are in bytes and bytes per second internally; the UI formats rates as Kbps or Mbps.

The fallback currently sums `utun` interface counters. If another VPN or network extension is active at the same time, its `utun` traffic may be included. If traffic reports look inflated, inspect interface selection and the TunnelKit shared-counter path before changing the UI formatting. Do not claim a counter fix is verified from compilation alone; check it during a real VPN session with traffic flowing.

Public IP lookup is performed by the app after connection. It tries `https://ifconfig.me/ip` first, then `api64.ipify.org` and `api.ipify.org` as JSON fallbacks. The fallback was verified because the ipify hosts were unreachable on the tested WireGuard route while ifconfig.me responded.

## User data and permissions

- Profile configuration is stored under the user's Application Support directory in `LiteVPN/profiles.json`; imported `.ovpn` and WireGuard files can contain private keys. Do not inspect, print, or commit actual user profile data.
- The selected profile ID and ordinary UI settings use standard app preferences.
- The VPN system extension persists independently of the menu bar UI. Quitting the app does not itself disconnect/remove the VPN service.
- macOS may require approval for the system extension in System Settings. On extension updates, `SystemExtensionInstaller` requests replacement for the same Team ID and bundle ID.
- The app asks for network client access for the VPN and public-IP request, user-selected read access for imported profiles, and the required App Group and Network Extension entitlements.

## Build locally

Requirements: macOS 26+, Xcode, XcodeGen (`brew install xcodegen`), and Go 1.17+ (`brew install go`). The first WireGuard build fetches Go modules. `LiteVPN.xcodeproj` is generated and ignored by Git; regenerate it after changing `project.yml` or when cloning the repository.

```bash
xcodegen generate --spec project.yml --project .
xcodebuild -project LiteVPN.xcodeproj \
  -scheme LiteVPN \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath Build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The unsigned local app is at `Build/DerivedData/Build/Products/Debug/LiteVPN.app`. It is suitable for compile checks, not direct installation of the system extension. For an installable release, use the signed distribution workflow below.

## Create a signed, notarized direct-distribution package

The local Developer ID provisioning profile names are:

- App: `LiteVPN App Developer ID Local`
- System extension: `LiteVPN Tunnel Developer ID Local`
- `notarytool` Keychain profile: `LiteVPN-Notary`

No Apple ID password, app-specific password, certificate private key, provisioning profile contents, or VPN profile should be committed. The notary credentials are stored in Keychain.

Before each release:

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Run `xcodegen generate --spec project.yml --project .` so the generated Xcode project reflects those values.
3. Build and validate the app, including a live VPN session for Network Extension or traffic-counter changes.
4. Run the release script with the local profile names:

   ```bash
   LITEVPN_APP_PROFILE="LiteVPN App Developer ID Local" \
   LITEVPN_TUNNEL_PROFILE="LiteVPN Tunnel Developer ID Local" \
   Scripts/release-direct.sh
   ```

5. Verify the app and embedded extension versions, `codesign --verify --deep --strict`, `spctl --assess --type execute`, and stapler validation before publishing.
6. Create a version tag and push both `main` and the tag. Upload only the notarized ZIP to the GitHub release:

   ```bash
   git push origin HEAD:main refs/tags/vX.Y.Z
   gh release create vX.Y.Z Build/DirectDistribution/LiteVPN-X.Y.Z.zip \
     --repo egemenince-git/LiteVPN \
     --title 'LiteVPN X.Y.Z — Release summary' \
     --notes-file Build/DirectDistribution/release-notes-X.Y.Z.md \
     --latest
   ```

Older broken releases should be marked superseded with a clear pointer to the replacement; do not delete release history unless asked.

## Current implementation note

Version 1.1.5 adds the `utun` interface fallback because the 1.1.4 app continued to show missing received/sent totals during a connected session. The code change is in commit `37a3f5a` and release tag `v1.1.5`. The release package was notarized and verified before publication. A successful compile or notarization does not establish that live traffic values are correct; validate against a real connection and traffic transfer.

## WireGuard implementation status

WireGuard uses the official WireGuard Apple implementation, vendored at revision `2fec12a6e1f6e3460b6ee483aa00ad29cddadab1`. On 2026-10-10, the signed and notarized 1.1.7 build was installed from `/Applications/LiteVPN.app`; the user confirmed a WireGuard ping, increasing traffic, and successful public IP lookup. OpenVPN profiles and their public IP lookup were also confirmed to continue working. The WireGuard feature has source on the `feature/wireguard` branch but has no GitHub release tag or release page yet.
