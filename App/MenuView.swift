import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import TunnelKit

struct MenuView: View {
    @EnvironmentObject private var vpn: VPNController
    @EnvironmentObject private var store: ProfileStore

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var importErrorMessage: String?
    @State private var hoveredProfileID: UUID?
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    connectionCard

                    if vpn.status == .connected {
                        trafficCard
                    }

                    if let message = vpn.lastErrorMessage ?? importErrorMessage {
                        errorCard(message)
                    }

                    profilesSection
                    settingsSection
                    footer
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 360, height: menuHeight)
        .background(Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDropTargeted ? Theme.green : Theme.cardStroke, lineWidth: isDropTargeted ? 2 : 1)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var menuHeight: CGFloat {
        let baseHeight: CGFloat = vpn.status == .connected ? 525 : 390
        let additionalProfiles = CGFloat(max(0, store.profiles.count - 1)) * 44
        let emptyStateHeight: CGFloat = store.profiles.isEmpty ? 42 : 0
        return min(maximumMenuHeight, baseHeight + additionalProfiles + emptyStateHeight)
    }

    private var maximumMenuHeight: CGFloat {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        return max(360, (screen?.visibleFrame.height ?? 720) - 40)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: vpn.status == .connected ? "lock.shield.fill" : "shield.lefthalf.filled")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(statusColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(connectionHeadline)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(connectionDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if vpn.status == .connected {
                publicIPRow
            }

            Button(action: toggleConnection) {
                HStack(spacing: 8) {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 11, weight: .bold))
                    Text(buttonText)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(buttonForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(buttonBackground.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .glassEffect(
                    .regular.tint(vpn.status == .disconnected ? Theme.green : Theme.red).interactive(),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(buttonBorder, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(vpn.isPreparingConnection || (vpn.status == .disconnected && store.selectedProfile == nil))
            .opacity(vpn.isPreparingConnection || (vpn.status == .disconnected && store.selectedProfile == nil) ? 0.5 : 1)

            if vpn.needsSystemExtensionApproval {
                Text("Approve LiteVPN in System Settings to finish enabling VPN.")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(LinearGradient(
            colors: [Theme.cardTop, Theme.cardBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .glassEffect(.regular.tint(statusColor.opacity(0.10)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }

    private var publicIPRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.blue)
            Text("Public IP")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)

            if vpn.isLoadingPublicIP {
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else if let address = vpn.publicIPAddress {
                Text(verbatim: address)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("Unavailable")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Button("Retry") {
                    vpn.refreshPublicIP()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.metricBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var connectionHeadline: String {
        switch vpn.status {
        case .connected: return NSLocalizedString("Secure connection", comment: "connected panel headline")
        case .connecting: return NSLocalizedString("Connecting", comment: "connection panel headline")
        case .disconnecting: return NSLocalizedString("Disconnecting", comment: "connection panel headline")
        case .disconnected: return NSLocalizedString("VPN is off", comment: "connection panel headline")
        }
    }

    private var connectionDetail: String {
        if vpn.status == .connected, let profile = store.selectedProfile {
            return profile.name
        }
        if vpn.status == .disconnected, let profile = store.selectedProfile {
            return String(format: NSLocalizedString("Ready with %@", comment: "selected profile detail"), profile.name)
        }
        return NSLocalizedString("Select a profile to get started", comment: "empty connection detail")
    }

    private var trafficCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Live Traffic", systemImage: "waveform.path")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Theme.green).frame(width: 5, height: 5)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(Theme.green)
                }
            }

            HStack(spacing: 10) {
                speedMetric(title: "Download", symbol: "arrow.down", color: Theme.blue, value: vpn.downloadSpeed)
                speedMetric(title: "Upload", symbol: "arrow.up", color: Theme.purple, value: vpn.uploadSpeed)
            }

            TrafficSparkline(samples: vpn.trafficSamples)
                .frame(height: 38)
                .padding(.top, 1)

            Rectangle().fill(Theme.cardStroke).frame(height: 1)

            HStack(spacing: 0) {
                sessionMetric(title: "Duration") {
                    if let date = vpn.connectedDate {
                        Text(date, style: .timer)
                    } else {
                        Text(verbatim: "—")
                    }
                }
                metricDivider
                sessionMetric(title: "Received") {
                    Text(verbatim: vpn.dataCount.map { format($0.received) } ?? "—")
                }
                metricDivider
                sessionMetric(title: "Sent") {
                    Text(verbatim: vpn.dataCount.map { format($0.sent) } ?? "—")
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }

    private func speedMetric(title: LocalizedStringKey, symbol: String, color: Color, value: UInt) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(verbatim: formatRate(value))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.metricBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sessionMetric<Value: View>(title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            value()
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricDivider: some View {
        Rectangle().fill(Theme.cardStroke).frame(width: 1, height: 24).padding(.horizontal, 8)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.red)
            Text(verbatim: message)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.red.opacity(0.18), lineWidth: 1))
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                HStack(spacing: 6) {
                    Text("Profiles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(store.profiles.count)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.card, in: Capsule())
                }
                Spacer()
                Button(action: importFromPanel) {
                    Label("Import", systemImage: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.green)
                }
                .buttonStyle(.plain)
            }

            if store.profiles.isEmpty {
                emptyState
            } else {
                VStack(spacing: 5) {
                    ForEach(sortedProfiles) { profile in
                        profileRow(profile)
                    }
                }
            }
        }
    }

    private var sortedProfiles: [Profile] {
        store.profiles.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text("Drop .ovpn files here to import")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("or use Import to browse files")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textSecondary.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(Theme.card.opacity(0.48), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        let isSelected = store.selectedProfileID == profile.id
        let isHovered = hoveredProfileID == profile.id
        return HStack(spacing: 9) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Theme.green : Theme.textSecondary.opacity(0.6))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: profile.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Spacer()
            if isSelected && vpn.status == .connected {
                Circle().fill(Theme.green).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isSelected ? 8 : 7)
        .background(isSelected ? Theme.green.opacity(0.11) : (isHovered ? Theme.card : .clear), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Theme.green.opacity(0.25) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredProfileID = hovering ? profile.id : nil
        }
        .onTapGesture {
            selectProfile(profile)
        }
        .contextMenu {
            Button("Rename") {
                renameProfile(profile)
            }
            Button("Delete", role: .destructive) {
                if vpn.status != .disconnected && store.selectedProfileID == profile.id {
                    vpn.disconnect()
                }
                store.delete(profile)
            }
        }
    }

    private func renameProfile(_ profile: Profile) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Rename Profile", comment: "rename profile dialog title")
        alert.informativeText = NSLocalizedString("Enter a new name for this profile.", comment: "rename profile dialog message")
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "rename profile save action"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel action"))

        let textField = NSTextField(string: profile.name)
        textField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard !store.rename(profile, to: textField.stringValue) else { return }

        let error = NSAlert()
        error.messageText = NSLocalizedString("Profile name unavailable", comment: "rename profile error title")
        error.informativeText = NSLocalizedString("Profile names must be non-empty and unique.", comment: "rename profile error message")
        error.addButton(withTitle: NSLocalizedString("OK", comment: "dismiss action"))
        error.runModal()
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Theme.cardStroke).frame(height: 1)
            settingRow(title: "Launch at Login", subtitle: nil, isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        .padding(.top, 1)
    }

    private func settingRow(title: LocalizedStringKey, subtitle: LocalizedStringKey?, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.green)
                .labelsHidden()
        }
    }

    private var footer: some View {
        HStack {
            Text(verbatim: "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary.opacity(0.75))
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 2)
    }

    private var statusColor: Color {
        switch vpn.status {
        case .connected: return Theme.green
        case .connecting, .disconnecting: return Theme.amber
        case .disconnected: return Theme.textSecondary
        }
    }

    private var buttonText: LocalizedStringKey {
        if vpn.isPreparingConnection { return "Preparing…" }
        switch vpn.status {
        case .connected: return "Disconnect"
        case .connecting: return "Cancel"
        case .disconnecting: return "Disconnecting…"
        case .disconnected: return "Connect"
        }
    }

    private var buttonIcon: String {
        if vpn.isPreparingConnection { return "hourglass" }
        switch vpn.status {
        case .connected: return "xmark"
        case .connecting: return "xmark"
        case .disconnecting: return "hourglass"
        case .disconnected: return "bolt.fill"
        }
    }

    private var buttonBackground: Color {
        vpn.status == .disconnected ? Theme.green : Theme.card
    }

    private var buttonForeground: Color {
        vpn.status == .disconnected ? Theme.buttonOnGreen : Theme.textPrimary
    }

    private var buttonBorder: Color {
        vpn.status == .disconnected ? Theme.green.opacity(0.75) : Theme.cardStroke
    }

    private func toggleConnection() {
        switch vpn.status {
        case .disconnected:
            if let profile = store.selectedProfile {
                vpn.connect(using: profile)
            }
        default:
            vpn.disconnect()
        }
    }

    private func selectProfile(_ profile: Profile) {
        guard store.selectedProfileID != profile.id else { return }
        store.selectedProfileID = profile.id
        if vpn.status == .connected || vpn.status == .connecting {
            vpn.connect(using: profile)
        }
    }

    private func importFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ovpn") ?? .data]
        panel.allowsMultipleSelection = true
        panel.message = NSLocalizedString("Choose .ovpn configuration files", comment: "open panel message")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        importURLs(panel.urls)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "ovpn" else { return }
                Task { @MainActor in importURLs([url]) }
            }
        }
        return handled
    }

    private func importURLs(_ urls: [URL]) {
        importErrorMessage = nil
        for url in urls {
            do {
                try store.importProfile(from: url)
            } catch {
                importErrorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    private func format(_ bytes: UInt) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    private func formatRate(_ bytesPerSecond: UInt) -> String {
        let bitsPerSecond = Double(bytesPerSecond) * 8
        guard bitsPerSecond > 0 else { return "0 Kbps" }

        let value: Double
        let unit: String
        if bitsPerSecond >= 1_000_000 {
            value = bitsPerSecond / 1_000_000
            unit = "Mbps"
        } else {
            value = bitsPerSecond / 1_000
            unit = "Kbps"
        }
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }
}

private struct TrafficSparkline: View {
    let samples: [TrafficSample]

    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(samples.map { max($0.download, $0.upload) }.max() ?? 0, 1)
            ZStack {
                Sparkline(values: samples.map(\.download), maxValue: maxValue)
                    .stroke(Theme.blue, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                Sparkline(values: samples.map(\.upload), maxValue: maxValue)
                    .stroke(Theme.purple, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if samples.count < 2 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geometry.size.height - 1))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - 1))
                    }
                    .stroke(Theme.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .accessibilityLabel("Live download and upload traffic chart")
    }
}

private struct Sparkline: Shape {
    let values: [UInt]
    let maxValue: UInt

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let denominator = CGFloat(values.count - 1)
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: rect.minX + rect.width * CGFloat(index) / denominator,
                y: rect.maxY - rect.height * CGFloat(value) / CGFloat(maxValue)
            )
        }
        return Path { path in
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }
}
