import Photos
import UIKit

enum PhotoLibraryAccess: Equatable {
    case notDetermined
    case allowed
    case denied
    case restricted

    var canSave: Bool {
        self == .allowed
    }

    var detail: String {
        switch self {
        case .notDetermined:
            "Add an optional copy to Photos. Permission is requested when enabled."
        case .allowed:
            "Add an optional copy to Photos after every recording."
        case .denied:
            "Photos permission is off. Open iPhone Settings to allow adding photos."
        case .restricted:
            "This iPhone currently restricts access to Photos."
        }
    }
}

final class PhotoLibrarySaver: NSObject {
    private var saveContinuation: CheckedContinuation<Void, Error>?

    func currentAccess() -> PhotoLibraryAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }

    func requestAccess() async -> PhotoLibraryAccess {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard currentStatus == .notDetermined else {
            return Self.map(currentStatus)
        }
        return Self.map(await PHPhotoLibrary.requestAuthorization(for: .addOnly))
    }

    func saveVideo(at url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path),
              FileManager.default.isReadableFile(atPath: url.path) else {
            throw PhotoLibrarySaveError.recordingUnavailable
        }

        guard (await requestAccess()).canSave else {
            throw PhotoLibrarySaveError.accessDenied
        }

        guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path) else {
            throw PhotoLibrarySaveError.incompatibleVideo
        }

        try await withCheckedThrowingContinuation { continuation in
            saveContinuation = continuation
            UISaveVideoAtPathToSavedPhotosAlbum(
                url.path,
                self,
                #selector(video(_:didFinishSavingWithError:contextInfo:)),
                nil
            )
        }
    }

    @objc private func video(
        _ videoPath: String,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let continuation = saveContinuation else { return }
        saveContinuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotoLibraryAccess {
        switch status {
        case .authorized, .limited:
            .allowed
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .restricted
        }
    }
}

enum PhotoLibrarySaveError: LocalizedError {
    case accessDenied
    case incompatibleVideo
    case recordingUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Camera Roll permission is off. Enable Photos access in iPhone Settings."
        case .incompatibleVideo:
            "This recording format is not compatible with the iPhone Camera Roll."
        case .recordingUnavailable:
            "The completed recording could not be read for Camera Roll export."
        }
    }
}
