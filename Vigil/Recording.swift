import Foundation

struct VigilRecording: Identifiable, Hashable {
    let url: URL
    let createdAt: Date

    var id: String {
        url.deletingPathExtension().lastPathComponent
    }

    var filename: String {
        url.lastPathComponent
    }

    var shortID: String {
        String(id.replacingOccurrences(of: "vigil-", with: "").prefix(8)).uppercased()
    }

    func utcTimestamp(at elapsedTime: TimeInterval = 0) -> String {
        let date = createdAt.addingTimeInterval(max(0, elapsedTime))
        return date.formatted(
            .iso8601
                .year()
                .month()
                .day()
                .dateSeparator(.dash)
                .time(includingFractionalSeconds: false)
                .timeSeparator(.colon)
                .timeZone(separator: .omitted)
        ) + "Z"
    }

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var fileSize: String {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize
        else {
            return "—"
        }

        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

enum RecordingFiles {
    static func directory() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Vigil Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        return directory
    }

    static func newRecordingURL() throws -> URL {
        try directory()
            .appendingPathComponent("vigil-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("mov")
    }

    static func load() -> [VigilRecording] {
        guard let directory = try? directory() else { return [] }
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension.lowercased() == "mov" }
            .map { url in
                let values = try? url.resourceValues(forKeys: keys)
                return VigilRecording(
                    url: url,
                    createdAt: values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
