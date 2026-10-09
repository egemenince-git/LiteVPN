import Foundation
import TunnelKitOpenVPN
import WireGuardKit

enum VPNProtocolKind: String, Codable {
    case openVPN
    case wireGuard
}

struct Profile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var protocolKind: VPNProtocolKind
    var configurationText: String
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, protocolKind, configurationText, ovpnText, createdAt
    }

    init(id: UUID, name: String, protocolKind: VPNProtocolKind, configurationText: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.protocolKind = protocolKind
        self.configurationText = configurationText
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        protocolKind = try values.decodeIfPresent(VPNProtocolKind.self, forKey: .protocolKind) ?? .openVPN
        configurationText = try values.decodeIfPresent(String.self, forKey: .configurationText)
            ?? values.decode(String.self, forKey: .ovpnText)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(protocolKind, forKey: .protocolKind)
        try values.encode(configurationText, forKey: .configurationText)
        try values.encode(createdAt, forKey: .createdAt)
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published var selectedProfileID: UUID? {
        didSet {
            UserDefaults.standard.set(selectedProfileID?.uuidString, forKey: "SelectedProfileID")
        }
    }

    var selectedProfile: Profile? {
        profiles.first { $0.id == selectedProfileID }
    }

    enum ImportError: LocalizedError {
        case unreadable
        case needsCredentials
        case invalidWireGuard

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return NSLocalizedString("Unable to read file contents", comment: "import error")
            case .needsCredentials:
                return NSLocalizedString(
                    "This profile requires username/password authentication. Only certificate-embedded profiles are supported.",
                    comment: "import error"
                )
            case .invalidWireGuard:
                return NSLocalizedString("This WireGuard configuration is invalid or unsupported.", comment: "import error")
            }
        }
    }

    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiteVPN", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("profiles.json")

        load()
        if let raw = UserDefaults.standard.string(forKey: "SelectedProfileID"),
           let id = UUID(uuidString: raw),
           profiles.contains(where: { $0.id == id }) {
            selectedProfileID = id
        } else {
            selectedProfileID = profiles.first?.id
        }
    }

    @discardableResult
    func importProfile(from url: URL) throws -> Profile {
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw ImportError.unreadable
        }

        let kind: VPNProtocolKind
        switch url.pathExtension.lowercased() {
        case "ovpn":
            let result = try OpenVPN.ConfigurationParser.parsed(fromContents: text)
            if result.configuration.authUserPass == true {
                throw ImportError.needsCredentials
            }
            kind = .openVPN
        case "conf", "wg", "wgconf":
            do {
                _ = try TunnelConfiguration(fromWgQuickConfig: text)
            } catch {
                throw ImportError.invalidWireGuard
            }
            kind = .wireGuard
        default:
            throw ImportError.unreadable
        }

        let baseName = url.deletingPathExtension().lastPathComponent
        let profile = Profile(
            id: UUID(),
            name: uniqueName(baseName),
            protocolKind: kind,
            configurationText: text,
            createdAt: Date()
        )
        profiles.append(profile)
        save()
        if selectedProfileID == nil {
            selectedProfileID = profile.id
        }
        return profile
    }

    func delete(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        save()
        if selectedProfileID == profile.id {
            selectedProfileID = profiles.first?.id
        }
    }

    @discardableResult
    func rename(_ profile: Profile, to newName: String) -> Bool {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !profiles.contains(where: { $0.id != profile.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }),
              let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return false
        }
        profiles[index].name = name
        save()
        return true
    }

    private func uniqueName(_ base: String) -> String {
        var name = base
        var counter = 2
        while profiles.contains(where: { $0.name == name }) {
            name = "\(base) \(counter)"
            counter += 1
        }
        return name
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            return
        }
        profiles = (try? JSONDecoder().decode([Profile].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
