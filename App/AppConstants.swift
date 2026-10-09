import Foundation

enum AppConstants {
    /// App Group, 与 entitlements 中 $(TeamIdentifierPrefix)group.com.egemenince.LiteVPN 一致
    static let appGroup = "99U7KZC748.group.com.egemenince.LiteVPN"

    /// 隧道扩展的 Bundle ID
    static let tunnelBundleId = "com.egemenince.LiteVPN.Tunnel"

    /// Mach service used by the Network Extension system extension.
    static let tunnelMachServiceName = "99U7KZC748.com.egemenince.LiteVPN.Tunnel"
}
