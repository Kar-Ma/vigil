import AVFoundation
import Foundation

struct RecordingCaptureMetadata: Sendable {
    let recordingID: String
    let startedAt: Date
    let cameraMode: String
    let appVersion: String

    init(outputURL: URL, startedAt: Date, cameraMode: RecordingMode) {
        recordingID = outputURL.deletingPathExtension().lastPathComponent
        self.startedAt = startedAt
        self.cameraMode = cameraMode.title

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        appVersion = "Vigil \(version) (\(build))"
    }

    nonisolated var shortID: String {
        String(recordingID.replacingOccurrences(of: "vigil-", with: "").prefix(8)).uppercased()
    }

    nonisolated var utcStartText: String {
        Self.utcFormatter.string(from: startedAt)
    }

    nonisolated var avMetadataItems: [AVMetadataItem] {
        [
            item(.quickTimeMetadataTitle, "Vigil Capture \(shortID)"),
            item(.quickTimeMetadataCreationDate, utcStartText),
            item(.quickTimeMetadataAuthor, "Vigil"),
            item(.quickTimeMetadataSoftware, appVersion),
            item(
                .quickTimeMetadataInformation,
                "recording-id=\(recordingID); camera-mode=\(cameraMode); captured-with=Vigil"
            ),
            item(
                .quickTimeMetadataComment,
                "Captured with Vigil. Embedded metadata provides context and is not independent proof of authenticity."
            )
        ]
    }

    private nonisolated func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let metadataItem = AVMutableMetadataItem()
        metadataItem.identifier = identifier
        metadataItem.value = value as NSString
        metadataItem.extendedLanguageTag = "und"
        return metadataItem
    }

    private nonisolated static var utcFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
