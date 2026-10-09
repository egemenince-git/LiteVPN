import Foundation
import NetworkExtension
import TunnelKit
import TunnelKitOpenVPN

struct TrafficSample: Identifiable {
    let id = UUID()
    let download: UInt
    let upload: UInt
}

private struct PublicIPResponse: Decodable {
    let ip: String
}

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: VPNStatus = .disconnected
    @Published private(set) var connectedDate: Date?
    @Published private(set) var dataCount: DataCount?
    @Published private(set) var downloadSpeed: UInt = 0
    @Published private(set) var uploadSpeed: UInt = 0
    @Published private(set) var trafficSamples: [TrafficSample] = []
    @Published private(set) var publicIPAddress: String?
    @Published private(set) var isLoadingPublicIP = false
    @Published private(set) var publicIPLookupFailed = false
    @Published private(set) var isPreparingConnection = false
    @Published private(set) var needsSystemExtensionApproval = false
    @Published var lastErrorMessage: String?

    private let vpn = NetworkExtensionVPN()
    private let systemExtensionInstaller = SystemExtensionInstaller()
    private var dataCountTimer: Timer?
    private var publicIPTask: Task<Void, Never>?
    private var previousTrafficCount: DataCount?
    private var previousTrafficDate: Date?

    init() {
        let nc = NotificationCenter.default
        // 直接读 userInfo, 避开 TunnelKit 便捷访问器在键缺失时的 fatalError
        nc.addObserver(forName: VPNNotification.didChangeStatus, object: nil, queue: .main) { [weak self] note in
            guard note.userInfo?["BundleIdentifier"] as? String == AppConstants.tunnelBundleId,
                  let status = note.userInfo?["Status"] as? VPNStatus else {
                return
            }
            let date = note.userInfo?["ConnectionDate"] as? Date
            Task { @MainActor in
                self?.statusDidChange(to: status, connectedAt: date)
            }
        }
        nc.addObserver(forName: VPNNotification.didFail, object: nil, queue: .main) { [weak self] note in
            let message = (note.userInfo?["Error"] as? Error)?.localizedDescription
            Task { @MainActor in
                self?.lastErrorMessage = message
            }
        }
        Task {
            await vpn.prepare()
        }
    }

    func connect(using profile: Profile) {
        guard !isPreparingConnection else { return }
        lastErrorMessage = nil
        needsSystemExtensionApproval = false
        isPreparingConnection = true
        Task {
            defer { isPreparingConnection = false }
            do {
                try await systemExtensionInstaller.activate {
                    self.needsSystemExtensionApproval = true
                }
                needsSystemExtensionApproval = false
                await vpn.prepare()

                let parsed = try OpenVPN.ConfigurationParser.parsed(fromContents: profile.ovpnText)
                var ovpnConfiguration = parsed.configuration
                if UserDefaults.standard.bool(forKey: "clashCompatMode") {
                    // Clash 兼容: 不接管默认路由, 只保留配置/服务器下发的具体网段路由,
                    // 让 Clash 的系统代理继续处理其余流量
                    var builder = ovpnConfiguration.builder()
                    builder.routingPolicies = []
                    ovpnConfiguration = builder.build()
                }
                var cfg = OpenVPN.ProviderConfiguration(
                    profile.name,
                    appGroup: AppConstants.appGroup,
                    configuration: ovpnConfiguration
                )
                cfg.shouldDebug = true
                cfg.debugLogPath = "debug.log"
                try await vpn.reconnect(
                    AppConstants.tunnelBundleId,
                    configuration: cfg,
                    extra: nil,
                    after: .seconds(1)
                )
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func disconnect() {
        guard !isPreparingConnection else { return }
        Task {
            await vpn.disconnect()
        }
    }

    private func statusDidChange(to newStatus: VPNStatus, connectedAt date: Date?) {
        status = newStatus
        connectedDate = date
        switch newStatus {
        case .connected:
            lastErrorMessage = nil
            startDataCountTimer()
            refreshPublicIP()
        case .disconnected:
            stopDataCountTimer()
            dataCount = nil
            resetTraffic()
            resetPublicIP()
        default:
            stopDataCountTimer()
            resetTraffic()
            resetPublicIP()
        }
    }

    func refreshPublicIP() {
        publicIPTask?.cancel()
        publicIPAddress = nil
        publicIPLookupFailed = false
        isLoadingPublicIP = true

        publicIPTask = Task {
            defer {
                if !Task.isCancelled {
                    isLoadingPublicIP = false
                }
            }

            do {
                var request = URLRequest(url: URL(string: "https://api64.ipify.org?format=json")!)
                request.timeoutInterval = 8
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled,
                      let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let result = try JSONDecoder().decode(PublicIPResponse.self, from: data)
                guard !result.ip.isEmpty else { throw URLError(.cannotParseResponse) }
                publicIPAddress = result.ip
            } catch {
                guard !Task.isCancelled else { return }
                publicIPLookupFailed = true
            }
        }
    }

    private func resetPublicIP() {
        publicIPTask?.cancel()
        publicIPTask = nil
        publicIPAddress = nil
        isLoadingPublicIP = false
        publicIPLookupFailed = false
    }

    private func startDataCountTimer() {
        dataCountTimer?.invalidate()
        resetTraffic()
        dataCountTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let count = UserDefaults(suiteName: AppConstants.appGroup)?.openVPNDataCount
            Task { @MainActor in
                self?.updateTraffic(with: count)
            }
        }
    }

    private func stopDataCountTimer() {
        dataCountTimer?.invalidate()
        dataCountTimer = nil
    }

    private func updateTraffic(with count: DataCount?) {
        guard let count else { return }
        let now = Date()
        dataCount = count

        if let previousTrafficCount, let previousTrafficDate {
            let elapsed = max(now.timeIntervalSince(previousTrafficDate), 0.1)
            let receivedDelta = count.received >= previousTrafficCount.received
                ? count.received - previousTrafficCount.received
                : count.received
            let sentDelta = count.sent >= previousTrafficCount.sent
                ? count.sent - previousTrafficCount.sent
                : count.sent
            downloadSpeed = UInt(Double(receivedDelta) / elapsed)
            uploadSpeed = UInt(Double(sentDelta) / elapsed)
        } else {
            downloadSpeed = 0
            uploadSpeed = 0
        }

        trafficSamples.append(TrafficSample(download: downloadSpeed, upload: uploadSpeed))
        if trafficSamples.count > 30 {
            trafficSamples.removeFirst(trafficSamples.count - 30)
        }
        previousTrafficCount = count
        previousTrafficDate = now
    }

    private func resetTraffic() {
        previousTrafficCount = nil
        previousTrafficDate = nil
        downloadSpeed = 0
        uploadSpeed = 0
        trafficSamples = []
    }
}
