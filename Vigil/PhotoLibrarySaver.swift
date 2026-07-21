import Photos

struct PhotoLibrarySaver {
    func saveVideo(at url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibrarySaveError.accessDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

enum PhotoLibrarySaveError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        "Camera Roll access is off. You can enable it in the iPhone Settings app."
    }
}
