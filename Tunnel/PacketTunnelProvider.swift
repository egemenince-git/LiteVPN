import Foundation
import NetworkExtension
import WireGuardKit
import TunnelKitOpenVPNAppExtension

final class PacketTunnelProvider: OpenVPNTunnelProvider {
    private var wireGuardSession = false

    private lazy var wireGuardAdapter = WireGuardAdapter(with: self) { level, message in
        NSLog("WireGuard [%@]: %@", level == .error ? "error" : "verbose", message)
    }

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if let providerConfiguration = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
           providerConfiguration["LiteVPN.Protocol"] as? String == "WireGuard" {
            wireGuardSession = true
            guard let text = providerConfiguration["LiteVPN.WireGuardConfiguration"] as? String,
                  let configuration = try? TunnelConfiguration(fromWgQuickConfig: text) else {
                completionHandler(WireGuardProviderError.invalidConfiguration)
                return
            }
            wireGuardAdapter.start(tunnelConfiguration: configuration) { error in
                completionHandler(error)
            }
            return
        }

        wireGuardSession = false
        // 每 2 秒向 App Group defaults 写一次流量统计 (单位: 毫秒)
        dataCountInterval = 2000
        super.startTunnel(options: options, completionHandler: completionHandler)
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        guard wireGuardSession else {
            super.stopTunnel(with: reason, completionHandler: completionHandler)
            return
        }
        wireGuardAdapter.stop { _ in
            completionHandler()
            #if os(macOS)
            // Matches the official provider's workaround for an Apple packet-tunnel shutdown bug.
            exit(0)
            #endif
        }
    }
}

private enum WireGuardProviderError: LocalizedError {
    case invalidConfiguration

    var errorDescription: String? {
        "The WireGuard profile could not be read by the tunnel extension."
    }
}
