import Foundation

public struct TrackerRepository {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> (trackers: [Tracker], unreadable: Int) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ([], 0) }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: fileURL))
        let trackers = entries.compactMap(\.tracker)
        return (trackers, entries.count - trackers.count)
    }

    private struct Entry: Decodable {
        let tracker: Tracker?
        init(from decoder: Decoder) { tracker = try? Tracker(from: decoder) }
    }

    public func backUp() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let copy = fileURL.deletingLastPathComponent().appendingPathComponent("trackers-backup-\(formatter.string(from: Date())).json")
        try FileManager.default.copyItem(at: fileURL, to: copy)
    }

    public func save(_ trackers: [Tracker]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(trackers)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}