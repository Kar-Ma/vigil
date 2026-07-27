import Foundation

enum ICloudAvailability: Equatable, Sendable {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case notConfigured(String)

    var title: String {
        switch self {
        case .checking: "Checking iCloud Drive"
        case .available: "iCloud Drive ready"
        case .noAccount: "Turn on iCloud Drive"
        case .restricted: "iCloud Drive restricted"
        case .temporarilyUnavailable: "iCloud Drive unavailable"
        case .notConfigured: "iCloud Drive setup needed"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            "Checking your iCloud Drive."
        case .available:
            "Save a visible copy in iCloud Drive › Vigil › Recordings."
        case .noAccount:
            "Sign in to iCloud and turn on iCloud Drive in iPhone Settings."
        case .restricted:
            "iCloud Drive is restricted on this iPhone."
        case .temporarilyUnavailable:
            "iCloud Drive is temporarily unavailable. Vigil will keep your Vault copy."
        case .notConfigured(let message):
            message
        }
    }

    var canUpload: Bool {
        self == .available
    }
}

struct ICloudRecordingSummary: Identifiable, Hashable, Sendable {
    let id: String
    let filename: String
    let createdAt: Date
    let fileSize: Int64?
    let url: URL
    let isUploaded: Bool

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedFileSize: String {
        guard let fileSize else { return "Stored in iCloud Drive" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

actor CloudUploader {
    static let containerIdentifier = "iCloud.com.karthikmahadevan.vigil"
    static let recordingsFolderName = "Recordings"

    private let fileManager = FileManager.default
    private let downloadTimeout: TimeInterval = 90

    func availability() -> ICloudAvailability {
        guard fileManager.ubiquityIdentityToken != nil else {
            return .noAccount
        }

        guard fileManager.url(
            forUbiquityContainerIdentifier: Self.containerIdentifier
        ) != nil else {
            return .notConfigured(
                "Vigil can’t open its iCloud Drive folder yet. Check iCloud Drive in iPhone Settings."
            )
        }

        return .available
    }

    func upload(
        filename: String,
        fileURL: URL,
        fileSize: Int64?
    ) async throws {
        let destination = try recordingDestination(filename: filename)

        let existingSize = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if !fileManager.fileExists(atPath: destination.path)
            || fileSize != existingSize.map(Int64.init) {
            try copyToICloudDrive(from: fileURL, to: destination)
        }

        try await waitUntilUploaded(destination)
    }

    func listRecordings() throws -> [ICloudRecordingSummary] {
        let directory = try recordingsDirectory()
        let keys: Set<URLResourceKey> = [
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .ubiquitousItemIsUploadedKey
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return urls
            .filter { $0.pathExtension.lowercased() == "mov" }
            .map { url in
                let values = try? url.resourceValues(forKeys: keys)
                return ICloudRecordingSummary(
                    id: url.deletingPathExtension().lastPathComponent,
                    filename: url.lastPathComponent,
                    createdAt: values?.creationDate
                        ?? values?.contentModificationDate
                        ?? .distantPast,
                    fileSize: values?.fileSize.map(Int64.init),
                    url: url,
                    isUploaded: values?.ubiquitousItemIsUploaded == true
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func downloadedURL(for summary: ICloudRecordingSummary) async throws -> URL {
        try await ensureDownloaded(summary.url)
        return summary.url
    }

    func delete(recordingID: String) throws {
        let destination = try recordingDestination(filename: "\(recordingID).mov")
        guard fileManager.fileExists(atPath: destination.path) else { return }
        try coordinatedDelete(destination)
    }

    static func friendlyMessage(for error: Error) -> String {
        if let driveError = error as? ICloudDriveError {
            switch driveError {
            case .containerUnavailable:
                return "Turn on iCloud Drive in iPhone Settings. The recording remains in Vigil Vault."
            case .downloadPending:
                return "The iCloud Drive copy is still downloading. Please try again shortly."
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            if nsError.code == NSFileWriteOutOfSpaceError {
                return "Your iCloud storage is full. The recording remains in Vigil Vault."
            }
            if nsError.code == NSFileNoSuchFileError {
                return "That iCloud Drive recording is no longer available."
            }
        }

        return "iCloud Drive couldn’t finish this request. The recording remains in Vigil Vault."
    }

    private func recordingsDirectory() throws -> URL {
        guard let container = fileManager.url(
            forUbiquityContainerIdentifier: Self.containerIdentifier
        ) else {
            throw ICloudDriveError.containerUnavailable
        }

        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        let recordings = documents.appendingPathComponent(
            Self.recordingsFolderName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: recordings,
            withIntermediateDirectories: true
        )
        return recordings
    }

    private func recordingDestination(filename: String) throws -> URL {
        try recordingsDirectory().appendingPathComponent(
            URL(fileURLWithPath: filename).lastPathComponent
        )
    }

    private func copyToICloudDrive(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try coordinatedDelete(destination)
        }

        let stagingURL = fileManager.temporaryDirectory
            .appendingPathComponent("vigil-icloud-\(UUID().uuidString)")
            .appendingPathExtension(source.pathExtension)
        try fileManager.copyItem(at: source, to: stagingURL)
        defer { try? fileManager.removeItem(at: stagingURL) }

        try fileManager.setUbiquitous(
            true,
            itemAt: stagingURL,
            destinationURL: destination
        )
    }

    private func coordinatedDelete(_ url: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?

        coordinator.coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try fileManager.removeItem(at: coordinatedURL)
            } catch {
                operationError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let operationError {
            throw operationError
        }
    }

    private func waitUntilUploaded(_ url: URL) async throws {
        let recordingID = url.deletingPathExtension().lastPathComponent

        while true {
            try Task.checkCancellation()

            let listedRecording = try? listRecordings().first {
                $0.id == recordingID
            }
            if listedRecording?.isUploaded == true {
                return
            }

            let values = try? url.resourceValues(
                forKeys: [
                    .ubiquitousItemIsUploadedKey,
                    .ubiquitousItemUploadingErrorKey
                ]
            )
            if let uploadError = values?.ubiquitousItemUploadingError {
                throw uploadError
            }
            if values?.ubiquitousItemIsUploaded == true {
                return
            }

            try await Task.sleep(for: .seconds(2))
        }
    }

    private func ensureDownloaded(_ url: URL) async throws {
        let initialValues = try? url.resourceValues(
            forKeys: [.ubiquitousItemDownloadingStatusKey]
        )
        if initialValues?.ubiquitousItemDownloadingStatus == .current {
            return
        }

        try fileManager.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(downloadTimeout)

        while Date() < deadline {
            try Task.checkCancellation()
            let values = try? url.resourceValues(
                forKeys: [
                    .ubiquitousItemDownloadingStatusKey,
                    .ubiquitousItemDownloadingErrorKey
                ]
            )
            if let downloadError = values?.ubiquitousItemDownloadingError {
                throw downloadError
            }
            if values?.ubiquitousItemDownloadingStatus == .current {
                return
            }

            try await Task.sleep(for: .seconds(1))
        }

        throw ICloudDriveError.downloadPending
    }

}

enum ICloudDriveError: Error {
    case containerUnavailable
    case downloadPending
}
