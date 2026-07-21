import Photos

private final class PhotoSaveAttempt: @unchecked Sendable {
    var createdAsset = false
}

struct PhotoLibrarySaver {
    func saveVideo(at url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path),
              FileManager.default.isReadableFile(atPath: url.path) else {
            throw PhotoLibrarySaveError.recordingUnavailable
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibrarySaveError.accessDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let attempt = PhotoSaveAttempt()
            PHPhotoLibrary.shared().performChanges {
                attempt.createdAsset = PHAssetChangeRequest
                    .creationRequestForAssetFromVideo(atFileURL: url) != nil
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success && attempt.createdAsset {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibrarySaveError.couldNotCreateAsset)
                }
            }
        }
    }
}

enum PhotoLibrarySaveError: LocalizedError {
    case accessDenied
    case recordingUnavailable
    case couldNotCreateAsset

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Camera Roll access is off. You can enable it in the iPhone Settings app."
        case .recordingUnavailable:
            "The completed recording could not be read for Camera Roll export."
        case .couldNotCreateAsset:
            "Photos could not create a Camera Roll copy of this recording."
        }
    }
}
