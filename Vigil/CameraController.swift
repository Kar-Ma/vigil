import AVFoundation
import Combine
import Foundation

enum CameraReadiness: Equatable {
    case idle
    case requestingPermission
    case ready
    case denied
    case unavailable
    case failed(String)
}

final class CameraController: NSObject, ObservableObject {
    @Published private(set) var readiness: CameraReadiness = .idle
    @Published private(set) var isRecording = false
    @Published private(set) var recordingStartedAt: Date?

    let session = AVCaptureSession()
    var onRecordingFinished: ((Result<URL, Error>) -> Void)?

    private let movieOutput = AVCaptureMovieFileOutput()
    private var isConfigured = false

    func prepare() async {
        guard readiness == .idle else { return }
        readiness = .requestingPermission

        let cameraAllowed = await requestAccess(for: .video)
        let microphoneAllowed = await requestAccess(for: .audio)
        guard cameraAllowed, microphoneAllowed else {
            readiness = .denied
            return
        }

        configureSession()
    }

    func startRecording() {
        guard readiness == .ready, !movieOutput.isRecording else { return }
        do {
            let url = try RecordingFiles.newRecordingURL()
            if let connection = movieOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            movieOutput.startRecording(to: url, recordingDelegate: self)
            isRecording = true
            recordingStartedAt = Date()
        } catch {
            readiness = .failed(error.localizedDescription)
        }
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    private func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func configureSession() {
        guard !isConfigured else {
            if !session.isRunning { session.startRunning() }
            readiness = .ready
            return
        }

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let microphone = AVCaptureDevice.default(for: .audio)
        else {
            readiness = .unavailable
            return
        }

        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            let microphoneInput = try AVCaptureDeviceInput(device: microphone)

            session.beginConfiguration()
            session.sessionPreset = .high
            guard
                session.canAddInput(cameraInput),
                session.canAddInput(microphoneInput),
                session.canAddOutput(movieOutput)
            else {
                session.commitConfiguration()
                readiness = .failed("The camera could not be configured on this device.")
                return
            }

            session.addInput(cameraInput)
            session.addInput(microphoneInput)
            session.addOutput(movieOutput)
            session.commitConfiguration()
            isConfigured = true
            session.startRunning()
            readiness = .ready
        } catch {
            readiness = .failed(error.localizedDescription)
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isRecording = false
            recordingStartedAt = nil

            if let error {
                try? FileManager.default.removeItem(at: outputFileURL)
                onRecordingFinished?(.failure(error))
                return
            }

            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: outputFileURL.path
            )
            onRecordingFinished?(.success(outputFileURL))
        }
    }
}
