import CloudKit
import Foundation

enum ICloudAvailability: Equatable {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case notConfigured(String)

    var title: String {
        switch self {
        case .checking: "Checking iCloud"
        case .available: "iCloud ready"
        case .noAccount: "Sign in to iCloud"
        case .restricted: "iCloud restricted"
        case .temporarilyUnavailable: "iCloud unavailable"
        case .notConfigured: "iCloud setup needed"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            "Checking whether this device can protect recordings in iCloud."
        case .available:
            "Completed recordings will upload to your private iCloud database."
        case .noAccount:
            "Sign in to iCloud in Settings. Recordings will remain safely stored on this device meanwhile."
        case .restricted:
            "This device does not currently allow private iCloud storage."
        case .temporarilyUnavailable:
            "iCloud cannot be reached right now. Vigil will keep the local recording."
        case .notConfigured(let message):
            message
        }
    }
}

struct CloudUploader {
    static let containerIdentifier = "iCloud.com.karma.vigil"

    private let container: CKContainer?

    init() {
        container = CloudKitConfiguration.isEnabled
            ? CKContainer(identifier: Self.containerIdentifier)
            : nil
    }

    func availability() async -> ICloudAvailability {
        guard let container else {
            return .notConfigured(
                "Apple Developer and CloudKit setup must be enabled before iCloud uploads can begin."
            )
        }
        do {
            switch try await container.accountStatus() {
            case .available: return ICloudAvailability.available
            case .noAccount: return ICloudAvailability.noAccount
            case .restricted: return ICloudAvailability.restricted
            case .temporarilyUnavailable: return ICloudAvailability.temporarilyUnavailable
            case .couldNotDetermine: return ICloudAvailability.temporarilyUnavailable
            @unknown default: return ICloudAvailability.temporarilyUnavailable
            }
        } catch {
            return ICloudAvailability.notConfigured(Self.friendlyMessage(for: error))
        }
    }

    func upload(_ recording: VigilRecording) async throws {
        guard let container else {
            throw CloudUploadError.notConfigured
        }
        let recordID = CKRecord.ID(recordName: recording.id)
        let record = CKRecord(recordType: "VigilRecording", recordID: recordID)
        record["createdAt"] = recording.createdAt as CKRecordValue
        record["filename"] = recording.filename as CKRecordValue
        record["video"] = CKAsset(fileURL: recording.url)
        _ = try await container.privateCloudDatabase.save(record)
    }

    static func friendlyMessage(for error: Error) -> String {
        if error is CloudUploadError {
            return "Apple Developer and CloudKit setup must be enabled before iCloud uploads can begin."
        }
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           let code = CKError.Code(rawValue: nsError.code) {
            switch code {
            case .notAuthenticated:
                return "Sign in to iCloud in Settings to enable cloud protection."
            case .quotaExceeded:
                return "Your iCloud storage is full. This recording remains on this device."
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                return "iCloud cannot be reached right now. This recording remains on this device."
            case .badContainer, .missingEntitlement, .permissionFailure:
                return "Apple Developer and CloudKit setup must be enabled before iCloud uploads can begin."
            default:
                break
            }
        }
        return "iCloud protection is not configured yet. This recording remains on this device."
    }
}

enum CloudUploadError: Error {
    case notConfigured
}

private enum CloudKitConfiguration {
    #if CLOUDKIT_ENABLED
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif
}
