import Foundation
import TunnelKitOpenVPNAppExtension

final class PacketTunnelProvider: OpenVPNTunnelProvider {
    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // 每 2 秒向 App Group defaults 写一次流量统计 (单位: 毫秒)
        dataCountInterval = 2000
        super.startTunnel(options: options, completionHandler: completionHandler)
    }
}
