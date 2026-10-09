# LiteVPN

[English](README.md) | **简体中文** | [Türkçe](README.tr.md)

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-green.svg)
![Swift](https://img.shields.io/badge/Swift-5-orange.svg)
![License GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-lightgray.svg)

极简的 **macOS OpenVPN 与 WireGuard 菜单栏客户端**. 点开即用, 常驻轻量, 没有账户系统, 没有推送, 没有更新弹窗.

Swift 菜单栏应用使用 [TunnelKit](https://github.com/partout-io/tunnelkit) 提供 OpenVPN, 使用 [WireGuard 官方 Apple 实现](https://github.com/WireGuard/wireguard-apple) 提供 WireGuard.

<p align="center"><img src="docs/screenshot-zh.png" width="560" alt="LiteVPN 菜单栏面板 (连接状态)"></p>

## 功能

- **菜单栏常驻** (无 Dock 图标), 一键连接 / 断开
- **导入 .ovpn**: 拖拽进面板或文件选择器, 导入时即时解析校验, 多配置切换
- **导入 WireGuard**: 支持 wg-quick `.conf`、`.wg` 和 `.wgconf` 配置并在导入时校验
- **Vitals 风格实时状态**: 连接时长, 实时上下行速度, 累计流量, 流量图表与公网 IP
- **多配置管理**: 导入、选择、重命名和删除 OpenVPN / WireGuard 配置, 按名称排序
- **断线自动重连** (TunnelKit 内置), **开机启动** (可选)
- 隧道作为 macOS Network Extension 系统扩展运行, 退出菜单栏应用不会移除 VPN 服务
- 界面双语: English / 简体中文 (跟随系统语言)
- 深色半透明菜单栏界面

刻意的减法: OpenVPN 仅支持证书内嵌 (`<ca>` / `<cert>` / `<key>` inline) 的配置, 不支持用户名密码认证; WireGuard 不支持 `PreUp` / `PostUp` 等自定义命令.

## 架构

```
┌─────────────────────────┐      ┌──────────────────────────────┐
│ LiteVPN.app (菜单栏)     │      │ LiteVPNTunnel.systemextension│
│ SwiftUI MenuBarExtra    │─────▶│ NEPacketTunnelProvider       │
│ SystemExtensionInstaller│ NE   │ ├─ TunnelKit OpenVPN 引擎    │
│ 配置管理 / 状态 / 流量    │◀─────│ └─ WireGuardKit + Go 后端   │
└─────────────────────────┘ AppGroup └──────────────────────────┘
```

- TunnelKit v6.3.2 已 vendor 至 `Vendor/tunnelkit/` 并剥离已归档的 WireGuard 代码, 修改声明见 [Vendor/tunnelkit/LITEVPN-MODIFICATIONS.md](Vendor/tunnelkit/LITEVPN-MODIFICATIONS.md)
- 官方 WireGuard Apple 源码位于 `Vendor/wireguard-apple/`; 构建系统扩展时会为 arm64 与 x86_64 编译 Go bridge
- 加密层通过 `.upToNextMinor` 锁定在 OpenSSL **3.5 LTS** 线 (维护期至 2030 年 4 月), 依赖解析只会升 3.5.x 内的 patch 版本, 不会漂移到短维护期的版本线

## 构建与直接分发

依赖: macOS 26 或更新版本, Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), Go 1.17+ (`brew install go`); 首次构建 WireGuard 时会下载 Go modules. 签名分发需要 Apple Developer Program 会员资格.

本地生成并构建:

```bash
xcodegen generate
xcodebuild -project LiteVPN.xcodeproj -scheme LiteVPN \
  -derivedDataPath Build/DerivedData -allowProvisioningUpdates build
```

若要在 Mac App Store 之外分发, 请使用 **Developer ID Application** 证书签名并对应用进行公证。在 Certificates, Identifiers & Profiles 中, 为两个 App ID (`com.egemenince.LiteVPN` 和 `com.egemenince.LiteVPN.Tunnel`) 启用 System Extension Packet Tunnel 能力, 并创建对应的 Developer ID 描述文件。工程使用 system extension 网络扩展权限和 hardened runtime.

将 `notarytool` 钥匙串配置文件命名为 `LiteVPN-Notary`, 设置两个描述文件名称后执行:

```bash
xcodegen generate
LITEVPN_APP_PROFILE="<应用 Developer ID 描述文件名>" \
LITEVPN_TUNNEL_PROFILE="<系统扩展 Developer ID 描述文件名>" \
Scripts/release-direct.sh
```

脚本会归档、签名、提交公证、装订公证票据, 并在 `Build/DirectDistribution/` 下生成 ZIP。首次运行时, macOS 可能要求用户在“系统设置”中批准 LiteVPN 的 VPN 系统扩展.

## 使用

1. 点击菜单栏盾牌图标
2. 拖入 `.ovpn` 或 WireGuard `.conf` 文件 (或点「+ 导入」)
3. 点「连接」

## 致谢

- [TunnelKit](https://github.com/partout-io/tunnelkit) by Davide De Rosa —— OpenVPN 协议引擎
- [WireGuard Apple](https://github.com/WireGuard/wireguard-apple) by WireGuard LLC —— WireGuardKit 与 Go 隧道后端 (MIT)
- [OpenSSL](https://github.com/partout-io/openssl-apple) —— 加密层 (3.5 LTS)

## 许可证

[GPL-3.0](LICENSE) (协议引擎 TunnelKit 为 GPL-3.0, 本项目随之采用).

## 作者

云中江树 · 微信公众号: 云中江树
