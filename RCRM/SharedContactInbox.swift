import Foundation

struct SharedContactItem: Codable, Identifiable {
    let id: String
    var name: String
    let phones: [String]
    let email: String
    let company: String
    let jobTitle: String
    var phoneLabels: [String]? = nil

    func phoneLabel(at index: Int) -> String {
        guard let labels = phoneLabels, labels.indices.contains(index) else { return "Phone" }
        let label = labels[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Phone" : label
    }
}

enum SharedContactInbox {
    static let group = "group.com.nickpulido.rcrm.shared"

    static func directory() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = container.appendingPathComponent("SharedContacts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func add(_ item: SharedContactItem) throws {
        let file = try directory().appendingPathComponent(item.id).appendingPathExtension("json")
        try JSONEncoder().encode(item).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func items() throws -> [SharedContactItem] {
        let files = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: [.creationDateKey])
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            return try? JSONDecoder().decode(SharedContactItem.self, from: data)
        }
    }

    static func remove(_ item: SharedContactItem) throws {
        let file = try directory().appendingPathComponent(item.id).appendingPathExtension("json")
        try FileManager.default.removeItem(at: file)
    }
}
