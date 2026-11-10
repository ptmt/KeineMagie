import Foundation
import KeineMagieCore

// This inbox contains only untrusted URLs. Authentication never leaves the app's
// existing private Keychain, and import always requires foreground confirmation.
enum PodcastShareInbox {
    static let group = "group.de.keinemagie.app"
    struct Item: Identifiable { let id: String; let url: String }
    private static func directory() throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = root.appendingPathComponent("PodcastInbox", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory
    }
    static func save(_ raw: String) throws {
        let value = try PodcastShareURL(raw)
        guard try items().count < 20 else { throw CocoaError(.fileWriteOutOfSpace) }
        let file = try directory().appendingPathComponent(UUID().uuidString + ".url")
        try Data(value.url.absoluteString.utf8).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func items() throws -> [Item] {
        let files = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return try files.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(20).compactMap { file in
            guard file.pathExtension == "url", UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else { return nil }
            let metadata = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard metadata.isRegularFile == true, metadata.isSymbolicLink != true, (metadata.fileSize ?? 4097) <= 4096,
                  let value = String(data: try Data(contentsOf: file), encoding: .utf8),
                  let validated = try? PodcastShareURL(value) else { return nil }
            return Item(id: file.lastPathComponent, url: validated.url.absoluteString)
        }
    }
    static func remove(_ item: Item) throws {
        guard item.id.hasSuffix(".url"), UUID(uuidString: String(item.id.dropLast(4))) != nil else { throw CocoaError(.fileReadInvalidFileName) }
        try FileManager.default.removeItem(at: directory().appendingPathComponent(item.id))
    }
}
