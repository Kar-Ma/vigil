import AVFoundation
import CallKit
import Combine
import Foundation
import UIKit

enum CameraReadiness: Equatable {
    case idle
    case requestingPermission
    case ready
    case denied
    case unavailable
    case callInProgress
    case failed(String)
}

final class CameraController: NSObject, ObservableObject {
    @Published private(set) var readiness: CameraReadiness = .idle
    @Published private(set) var isRecording = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var isChangingMode = false
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var selectedMode: RecordingMode
    @Published private(set) var session: AVCaptureSession {
        didSet { observeSessionInterruptions() }
    }

    let isDualCameraSupported: Bool
    let primaryPreviewLayer = AVCaptureVideoPreviewLayer()
    let secondaryPreviewLayer = AVCaptureVideoPreviewLayer()
    var onRecordingFinished: ((Result<URL, Error>) -> Void)?
    var onRecordingProtectedFromInterruption: (() -> Void)?
    var onRecordingResumedAfterInterruption: (() -> Void)?

    private let movieOutput = AVCaptureMovieFileOutput()
    private let dualProcessor = DualCameraProcessor()
    private let callObserver = CXCallObserver()
    private var isPersistentMultiCamConfigured = false
    private var backOutputConnection: AVCaptureConnection?
    private var frontOutputConnection: AVCaptureConnection?
    private var backPreviewConnection: AVCaptureConnection?
    private var frontPreviewConnection: AVCaptureConnection?
    private var backRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var frontRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []
    private var sessionObserverTokens: [NSObjectProtocol] = []
    private var shouldResumeAfterInterruption = false
    private var isAppActive = true
    private var finalizationBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var callRecoveryTask: Task<Void, Never>?

    init(initialMode: RecordingMode) {
        isDualCameraSupported = AVCaptureMultiCamSession.isMultiCamSupported
        selectedMode = initialMode == .dual && !isDualCameraSupported ? .rear : initialMode
        session = AVCaptureMultiCamSession.isMultiCamSupported
            ? AVCaptureMultiCamSession()
            : AVCaptureSession()
        super.init()

        primaryPreviewLayer.videoGravity = .resizeAspectFill
        secondaryPreviewLayer.videoGravity = .resizeAspectFill
        callObserver.setDelegate(self, queue: .main)
        observeSessionInterruptions()
    }

    deinit {
        callRecoveryTask?.cancel()
        for token in sessionObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func prepare() async {
        if readiness == .ready {
            if !session.isRunning {
                session.startRunning()
                readiness = session.isRunning
                    ? .ready
                    : unavailableReadiness(
                        defaultMessage: "The camera session could not restart."
                    )
            }
            return
        }

        // A locked-device launch can briefly make the camera unavailable while
        // iOS completes authentication. Retry that transient failure once the
        // scene is active instead of leaving the preview permanently black.
        guard readiness == .idle || isRetryableFailure else { return }
        readiness = .requestingPermission

        let cameraAllowed = await requestAccess(for: .video)
        let microphoneAllowed = await requestAccess(for: .audio)
        guard cameraAllowed, microphoneAllowed else {
            readiness = .denied
            return
        }

        configureSelectedMode()
    }

    private var isRetryableFailure: Bool {
        if case .failed = readiness { return true }
        return readiness == .callInProgress
    }

    func selectMode(_ mode: RecordingMode) {
        guard !isRecording, !isFinalizing, !isChangingMode else { return }
        guard mode != .dual || isDualCameraSupported else { return }
        guard selectedMode != mode else { return }

        selectedMode = mode
        guard readiness != .idle, readiness != .requestingPermission else { return }

        if isDualCameraSupported, isPersistentMultiCamConfigured {
            dualProcessor.setMode(mode)
            applyActiveMultiCamMode()
            return
        }

        isChangingMode = true
        configureSelectedMode()
        isChangingMode = false
    }

    func startRecording() {
        guard readiness == .ready, !isRecording, !isFinalizing else { return }

        do {
            let url = try RecordingFiles.newRecordingURL()
            let startedAt = Date()
            let metadata = RecordingCaptureMetadata(
                outputURL: url,
                startedAt: startedAt,
                cameraMode: selectedMode
            )
            if isDualCameraSupported {
                applyCaptureRotationSnapshot()
                try dualProcessor.startRecording(to: url, metadata: metadata)
            } else {
                guard !movieOutput.isRecording else { return }
                movieOutput.metadata = metadata.avMetadataItems
                movieOutput.startRecording(to: url, recordingDelegate: self)
            }
            isRecording = true
            recordingStartedAt = startedAt
            shouldResumeAfterInterruption = false
        } catch {
            readiness = .failed(error.localizedDescription)
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        if isDualCameraSupported {
            isRecording = false
            isFinalizing = true
            recordingStartedAt = nil
            dualProcessor.stopRecording { [weak self] result in
                DispatchQueue.main.async {
                    self?.finishRecording(result)
                }
            }
        } else if movieOutput.isRecording {
            isRecording = false
            isFinalizing = true
            recordingStartedAt = nil
            movieOutput.stopRecording()
        }
    }

    func appWillLeaveForeground() {
        isAppActive = false
        protectActiveRecordingFromInterruption()
    }

    func appDidBecomeActive() {
        isAppActive = true
        if !hasActiveCall, readiness == .callInProgress || shouldResumeAfterInterruption {
            scheduleRecoveryAfterCall()
        } else {
            recoverCaptureSessionAndResumeIfPossible()
        }
    }

    private func configureSelectedMode() {
        readiness = .requestingPermission

        do {
            if isDualCameraSupported {
                if !isPersistentMultiCamConfigured {
                    try configurePersistentMultiCameraSession()
                } else {
                    dualProcessor.setMode(selectedMode)
                    applyActiveMultiCamMode()
                }
            } else {
                tearDownCurrentSession()
                try configureSingleCameraSession(position: selectedMode == .front ? .front : .back)
            }

            session.startRunning()
            readiness = session.isRunning
                ? .ready
                : unavailableReadiness(defaultMessage: "The camera session could not start.")
        } catch CameraConfigurationError.cameraUnavailable {
            readiness = .unavailable
        } catch {
            readiness = unavailableReadiness(defaultMessage: error.localizedDescription)
        }
    }

    private func tearDownCurrentSession() {
        if session.isRunning {
            session.stopRunning()
        }

        session.beginConfiguration()
        for connection in session.connections where connection.videoPreviewLayer != nil {
            session.removeConnection(connection)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        for input in session.inputs {
            session.removeInput(input)
        }
        session.commitConfiguration()

        primaryPreviewLayer.session = nil
        secondaryPreviewLayer.session = nil
        rotationObservations.removeAll()
        backRotationCoordinator = nil
        frontRotationCoordinator = nil
        dualProcessor.reset()
    }

    private func configureSingleCameraSession(position: AVCaptureDevice.Position) throws {
        let newSession = AVCaptureSession()
        newSession.beginConfiguration()
        newSession.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let microphone = AVCaptureDevice.default(for: .audio) else {
            newSession.commitConfiguration()
            throw CameraConfigurationError.cameraUnavailable
        }

        let cameraInput = try AVCaptureDeviceInput(device: camera)
        let microphoneInput = try AVCaptureDeviceInput(device: microphone)
        guard newSession.canAddInput(cameraInput),
              newSession.canAddInput(microphoneInput),
              newSession.canAddOutput(movieOutput) else {
            newSession.commitConfiguration()
            throw CameraConfigurationError.cannotConfigureSession
        }

        newSession.addInput(cameraInput)
        newSession.addInput(microphoneInput)
        newSession.addOutput(movieOutput)
        newSession.commitConfiguration()
        session = newSession

        primaryPreviewLayer.session = newSession
        secondaryPreviewLayer.session = nil

        if let previewConnection = primaryPreviewLayer.connection {
            if previewConnection.isVideoRotationAngleSupported(90) {
                previewConnection.videoRotationAngle = 90
            }
            if position == .front {
                previewConnection.automaticallyAdjustsVideoMirroring = false
                previewConnection.isVideoMirrored = true
            }
        }

        if let movieConnection = movieOutput.connection(with: .video) {
            if movieConnection.isVideoRotationAngleSupported(90) {
                movieConnection.videoRotationAngle = 90
            }
            movieConnection.automaticallyAdjustsVideoMirroring = false
            movieConnection.isVideoMirrored = false
        }
    }

    private func configurePersistentMultiCameraSession() throws {
        guard isDualCameraSupported else {
            throw CameraConfigurationError.dualCameraUnsupported
        }

        guard let multiSession = session as? AVCaptureMultiCamSession else {
            throw CameraConfigurationError.cannotConfigureSession
        }
        primaryPreviewLayer.setSessionWithNoConnection(multiSession)
        secondaryPreviewLayer.setSessionWithNoConnection(multiSession)
        multiSession.beginConfiguration()

        guard let backCamera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ),
        let frontCamera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ),
        let microphone = AVCaptureDevice.default(for: .audio) else {
            multiSession.commitConfiguration()
            throw CameraConfigurationError.cameraUnavailable
        }

        try configureMultiCamFormat(for: backCamera)
        try configureMultiCamFormat(for: frontCamera)

        let backInput = try AVCaptureDeviceInput(device: backCamera)
        let frontInput = try AVCaptureDeviceInput(device: frontCamera)
        let microphoneInput = try AVCaptureDeviceInput(device: microphone)

        guard multiSession.canAddInput(backInput),
              multiSession.canAddInput(frontInput),
              multiSession.canAddInput(microphoneInput) else {
            multiSession.commitConfiguration()
            throw CameraConfigurationError.cannotConfigureSession
        }
        multiSession.addInputWithNoConnections(backInput)
        multiSession.addInputWithNoConnections(frontInput)
        multiSession.addInputWithNoConnections(microphoneInput)

        guard let backPort = backInput.ports(for: .video,
                                             sourceDeviceType: backCamera.deviceType,
                                             sourceDevicePosition: .back).first,
              let frontPort = frontInput.ports(for: .video,
                                               sourceDeviceType: frontCamera.deviceType,
                                               sourceDevicePosition: .front).first,
              let microphonePort = microphoneInput.ports(for: .audio,
                                                          sourceDeviceType: microphone.deviceType,
                                                          sourceDevicePosition: .back).first
                ?? microphoneInput.ports.first(where: { $0.mediaType == .audio }) else {
            multiSession.commitConfiguration()
            throw CameraConfigurationError.cannotConfigureSession
        }

        let backOutput = dualProcessor.backVideoOutput
        let frontOutput = dualProcessor.frontVideoOutput
        let audioOutput = dualProcessor.audioOutput
        guard multiSession.canAddOutput(backOutput),
              multiSession.canAddOutput(frontOutput),
              multiSession.canAddOutput(audioOutput) else {
            multiSession.commitConfiguration()
            throw CameraConfigurationError.cannotConfigureSession
        }
        multiSession.addOutputWithNoConnections(backOutput)
        multiSession.addOutputWithNoConnections(frontOutput)
        multiSession.addOutputWithNoConnections(audioOutput)

        let backOutputConnection = AVCaptureConnection(inputPorts: [backPort], output: backOutput)
        let frontOutputConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
        let audioConnection = AVCaptureConnection(inputPorts: [microphonePort], output: audioOutput)
        let backPreviewConnection = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: primaryPreviewLayer)
        let frontPreviewConnection = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: secondaryPreviewLayer)

        frontOutputConnection.automaticallyAdjustsVideoMirroring = false
        frontOutputConnection.isVideoMirrored = false
        frontPreviewConnection.automaticallyAdjustsVideoMirroring = false
        frontPreviewConnection.isVideoMirrored = true

        for connection in [
            backOutputConnection,
            frontOutputConnection,
            audioConnection,
            backPreviewConnection,
            frontPreviewConnection
        ] {
            guard multiSession.canAddConnection(connection) else {
                multiSession.commitConfiguration()
                throw CameraConfigurationError.cannotConfigureSession
            }
            multiSession.addConnection(connection)
        }

        multiSession.commitConfiguration()
        guard multiSession.hardwareCost <= 1 else {
            throw CameraConfigurationError.dualCameraCostTooHigh
        }
        self.backOutputConnection = backOutputConnection
        self.frontOutputConnection = frontOutputConnection
        self.backPreviewConnection = backPreviewConnection
        self.frontPreviewConnection = frontPreviewConnection
        configureRotationTracking(backCamera: backCamera, frontCamera: frontCamera)
        isPersistentMultiCamConfigured = true
        dualProcessor.setMode(selectedMode)
        applyActiveMultiCamMode()
    }

    private func configureRotationTracking(
        backCamera: AVCaptureDevice,
        frontCamera: AVCaptureDevice
    ) {
        rotationObservations.removeAll()

        let backCoordinator = AVCaptureDevice.RotationCoordinator(
            device: backCamera,
            previewLayer: primaryPreviewLayer
        )
        let frontCoordinator = AVCaptureDevice.RotationCoordinator(
            device: frontCamera,
            previewLayer: secondaryPreviewLayer
        )
        backRotationCoordinator = backCoordinator
        frontRotationCoordinator = frontCoordinator

        rotationObservations = [
            backCoordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                assert(Thread.isMainThread)
                MainActor.assumeIsolated {
                    self?.applyRotation(
                        coordinator.videoRotationAngleForHorizonLevelPreview,
                        to: self?.backPreviewConnection
                    )
                }
            },
            frontCoordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                assert(Thread.isMainThread)
                MainActor.assumeIsolated {
                    self?.applyRotation(
                        coordinator.videoRotationAngleForHorizonLevelPreview,
                        to: self?.frontPreviewConnection
                    )
                }
            },
            backCoordinator.observe(
                \.videoRotationAngleForHorizonLevelCapture,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                assert(Thread.isMainThread)
                MainActor.assumeIsolated {
                    self?.applyCaptureRotationSnapshot()
                }
            },
            frontCoordinator.observe(
                \.videoRotationAngleForHorizonLevelCapture,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                assert(Thread.isMainThread)
                MainActor.assumeIsolated {
                    self?.applyCaptureRotationSnapshot()
                }
            }
        ]
    }

    private func applyCaptureRotationSnapshot() {
        guard !isRecording, !isFinalizing else { return }
        if let backRotationCoordinator {
            applyRotation(
                backRotationCoordinator.videoRotationAngleForHorizonLevelCapture,
                to: backOutputConnection
            )
        }
        if let frontRotationCoordinator {
            applyRotation(
                frontRotationCoordinator.videoRotationAngleForHorizonLevelCapture,
                to: frontOutputConnection
            )
        }
    }

    private func applyRotation(_ angle: CGFloat, to connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    private func applyActiveMultiCamMode() {
        let usesBackCamera = selectedMode == .rear || selectedMode == .dual
        let usesFrontCamera = selectedMode == .front || selectedMode == .dual
        backOutputConnection?.isEnabled = usesBackCamera
        backPreviewConnection?.isEnabled = usesBackCamera
        frontOutputConnection?.isEnabled = usesFrontCamera
        frontPreviewConnection?.isEnabled = usesFrontCamera
    }

    private func configureMultiCamFormat(for device: AVCaptureDevice) throws {
        let formats = device.formats.filter { format in
            guard format.isMultiCamSupported else { return false }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let pixels = Int(dimensions.width) * Int(dimensions.height)
            let supportsThirtyFPS = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
            return pixels <= 1280 * 720 && supportsThirtyFPS
        }

        guard let format = formats.max(by: { left, right in
            let leftDimensions = CMVideoFormatDescriptionGetDimensions(left.formatDescription)
            let rightDimensions = CMVideoFormatDescriptionGetDimensions(right.formatDescription)
            return Int(leftDimensions.width) * Int(leftDimensions.height)
                < Int(rightDimensions.width) * Int(rightDimensions.height)
        }) else {
            throw CameraConfigurationError.dualCameraUnsupported
        }

        try device.lockForConfiguration()
        device.activeFormat = format
        let frameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
        device.unlockForConfiguration()
    }

    private func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }

    private func finishRecording(_ result: Result<URL, Error>) {
        isRecording = false
        isFinalizing = false
        recordingStartedAt = nil

        if case .success(let outputURL) = result {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: outputURL.path
            )
        }
        onRecordingFinished?(result)
        endFinalizationBackgroundTask()
        recoverCaptureSessionAndResumeIfPossible()
    }

    private func protectActiveRecordingFromInterruption() {
        guard isRecording else { return }
        shouldResumeAfterInterruption = true
        beginFinalizationBackgroundTask()
        onRecordingProtectedFromInterruption?()
        stopRecording()
    }

    private func recoverCaptureSessionAndResumeIfPossible() {
        guard isAppActive,
              readiness != .idle,
              readiness != .requestingPermission,
              !session.inputs.isEmpty else { return }

        if !session.isRunning {
            session.startRunning()
        }
        guard session.isRunning, !session.isInterrupted else {
            readiness = unavailableReadiness(
                defaultMessage: "The camera session could not restart."
            )
            return
        }

        readiness = .ready
        applyCaptureRotationSnapshot()
        resumeRecordingAfterInterruptionIfNeeded()
    }

    private func resumeRecordingAfterInterruptionIfNeeded() {
        guard shouldResumeAfterInterruption, !isRecording, !isFinalizing else { return }
        startRecording()
        if isRecording {
            onRecordingResumedAfterInterruption?()
        } else {
            shouldResumeAfterInterruption = true
        }
    }

    private func handleCallStateChanged() {
        if hasActiveCall {
            callRecoveryTask?.cancel()
            if !session.isRunning || session.isInterrupted {
                readiness = .callInProgress
            }
            return
        }

        scheduleRecoveryAfterCall()
    }

    private func scheduleRecoveryAfterCall() {
        callRecoveryTask?.cancel()
        callRecoveryTask = Task { @MainActor [weak self] in
            guard let self, self.isAppActive, !self.hasActiveCall else { return }
            self.readiness = .requestingPermission

            let retryDelays: [Duration] = [.milliseconds(350), .seconds(1), .seconds(2)]
            for delay in retryDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, self.isAppActive, !self.hasActiveCall else { return }
                guard !self.isFinalizing else { continue }

                if self.restartCaptureSessionAfterCall() {
                    return
                }
            }

            self.readiness = .failed(
                "The camera is still recovering after the call. Leave Vigil and return to try again."
            )
        }
    }

    private func restartCaptureSessionAfterCall() -> Bool {
        if session.isRunning {
            session.stopRunning()
        }
        session.startRunning()

        guard session.isRunning, !session.isInterrupted else { return false }
        readiness = .ready
        resumeRecordingAfterInterruptionIfNeeded()
        return true
    }

    private var hasActiveCall: Bool {
        callObserver.calls.contains { !$0.hasEnded }
    }

    private func unavailableReadiness(defaultMessage: String) -> CameraReadiness {
        hasActiveCall ? .callInProgress : .failed(defaultMessage)
    }

    private func observeSessionInterruptions() {
        for token in sessionObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        sessionObserverTokens.removeAll()

        let center = NotificationCenter.default
        let interruptedToken = center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.protectActiveRecordingFromInterruption()
            }
        }
        let interruptionEndedToken = center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recoverCaptureSessionAndResumeIfPossible()
            }
        }
        sessionObserverTokens = [interruptedToken, interruptionEndedToken]
    }

    private func beginFinalizationBackgroundTask() {
        guard finalizationBackgroundTask == .invalid else { return }
        finalizationBackgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "Finalize Vigil recording"
        ) { [weak self] in
            Task { @MainActor in
                self?.endFinalizationBackgroundTask()
            }
        }
    }

    private func endFinalizationBackgroundTask() {
        guard finalizationBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(finalizationBackgroundTask)
        finalizationBackgroundTask = .invalid
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
            if let error {
                let errorDetails = error as NSError
                let didFinishSuccessfully =
                    (errorDetails.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? NSNumber)?.boolValue
                    ?? false
                if didFinishSuccessfully {
                    finishRecording(.success(outputFileURL))
                } else {
                    try? FileManager.default.removeItem(at: outputFileURL)
                    finishRecording(.failure(error))
                }
            } else {
                finishRecording(.success(outputFileURL))
            }
        }
    }
}

extension CameraController: CXCallObserverDelegate {
    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        Task { @MainActor [weak self] in
            self?.handleCallStateChanged()
        }
    }
}

enum CameraConfigurationError: LocalizedError {
    case cameraUnavailable
    case cannotConfigureSession
    case dualCameraUnsupported
    case dualCameraCostTooHigh

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            "The requested camera is unavailable on this iPhone."
        case .cannotConfigureSession:
            "Vigil could not configure this camera mode."
        case .dualCameraUnsupported:
            "Front + Rear recording is not supported on this iPhone."
        case .dualCameraCostTooHigh:
            "This iPhone cannot run the selected Front + Rear camera quality safely."
        }
    }
}
