import Foundation
import NetworkExtension
import TunnelKit
import WireGuardKit

struct WireGuardProviderConfiguration: NetworkExtensionConfiguration {
    let title: String
    let configurationText: String

    func asTunnelProtocol(
        withBundleIdentifier bundleIdentifier: String,
        extra: NetworkExtensionExtra?
    ) throws -> NETunnelProviderProtocol {
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = bundleIdentifier
        let parsed = try TunnelConfiguration(fromWgQuickConfig: configurationText)
        tunnelProtocol.serverAddress = parsed.peers.compactMap(\.endpoint).first?.stringRepresentation ?? "Unspecified"
        tunnelProtocol.disconnectOnSleep = extra?.disconnectsOnSleep ?? false
        tunnelProtocol.providerConfiguration = [
            "LiteVPN.Protocol": "WireGuard",
            "LiteVPN.WireGuardConfiguration": configurationText
        ]
        #if !os(tvOS)
        tunnelProtocol.includeAllNetworks = extra?.killSwitch ?? false
        #endif
        return tunnelProtocol
    }
}
