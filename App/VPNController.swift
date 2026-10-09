import Foundation
import Darwin
import NetworkExtension
import TunnelKit
import TunnelKitOpenVPN

/// Reads macOS utun byte counters when the extension's shared counter is unavailable.
private final class SystemTunnelTrafficCounter {
    private var baseline: DataCount?

    func begin() {
        baseline = Self.snapshot()
    }

    func reset() {
        baseline = nil
    }

    func current() -> DataCount? {
        guard let baseline, let snapshot = Self.snapshot() else { return nil }
        return DataCount(
            snapshot.received >= baseline.received ? snapshot.received - baseline.received : snapshot.received,
            snapshot.sent >= baseline.sent ? snapshot.sent - baseline.sent : snapshot.sent
        )
    }

    private static func snapshot() -> DataCount? {
        var firstInterface: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstInterface) == 0, let firstInterface else { return nil }
        defer { freeifaddrs(firstInterface) }

        var received: UInt = 0
        var sent: UInt = 0
        var foundTunnel = false
        var interface = firstInterface

        repeat {
            let entry = interface.pointee
            if let address = entry.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let name = entry.ifa_name,
               String(cString: name).hasPrefix("utun"),
               let rawData = entry.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                received &+= UInt(data.ifi_ibytes)
                sent &+= UInt(data.ifi_obytes)
                foundTunnel = true
            }
            guard let next = entry.ifa_next else { break }
            interface = next
        } while true

        return foundTunnel ? DataCount(received, sent) : nil
    }
}

struct TrafficSample: Identifiable {
    let id = UUID()
    let download: UInt
    let upload: UInt
}

private struct PublicIPResponse: Decodable {
    let ip: String
}

private enum PublicIPEndpoint {
    case plainText(URL)
    case json(URL)
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
    private let systemTrafficCounter = SystemTunnelTrafficCounter()
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

                switch profile.protocolKind {
                case .wireGuard:
                    let cfg = WireGuardProviderConfiguration(
                        title: profile.name,
                        configurationText: profile.configurationText
                    )
                    try await vpn.reconnect(
                        AppConstants.tunnelBundleId,
                        configuration: cfg,
                        extra: nil,
                        after: .seconds(1)
                    )
                case .openVPN:
                    let parsed = try OpenVPN.ConfigurationParser.parsed(fromContents: profile.configurationText)
                    var ovpnConfiguration = parsed.configuration
                    if UserDefaults.standard.bool(forKey: "clashCompatMode") {
                        // Clash compatibility leaves the default route alone and routes only VPN subnets.
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
                }
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
            systemTrafficCounter.begin()
            startDataCountTimer()
            refreshPublicIP()
        case .disconnected:
            stopDataCountTimer()
            systemTrafficCounter.reset()
            dataCount = nil
            resetTraffic()
            resetPublicIP()
        default:
            stopDataCountTimer()
            systemTrafficCounter.reset()
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
                publicIPAddress = try await lookupPublicIP()
            } catch {
                guard !Task.isCancelled else { return }
                publicIPLookupFailed = true
            }
        }
    }

    private func lookupPublicIP() async throws -> String {
        let endpoints: [PublicIPEndpoint] = [
            .plainText(URL(string: "https://ifconfig.me/ip")!),
            .json(URL(string: "https://api64.ipify.org?format=json")!),
            .json(URL(string: "https://api.ipify.org?format=json")!)
        ]
        var lastError: Error = URLError(.cannotLoadFromNetwork)

        for endpoint in endpoints {
            guard !Task.isCancelled else { throw CancellationError() }
            let url: URL
            switch endpoint {
            case .plainText(let value), .json(let value):
                url = value
            }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/json, text/plain", forHTTPHeaderField: "Accept")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let candidate: String?
                switch endpoint {
                case .plainText:
                    candidate = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                case .json:
                    candidate = try? JSONDecoder().decode(PublicIPResponse.self, from: data).ip
                }

                if let candidate, isIPAddress(candidate) {
                    return candidate
                }
                throw URLError(.cannotParseResponse)
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        if value.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return true
        }
        var ipv6 = in6_addr()
        return value.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1
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
            Task { @MainActor in
                guard let self else { return }
                let count = UserDefaults(suiteName: AppConstants.appGroup)?.openVPNDataCount
                    ?? self.systemTrafficCounter.current()
                self.updateTraffic(with: count)
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
