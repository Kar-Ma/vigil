import Combine
import Foundation

struct CaptureNotice: Equatable {
    enum Tone: Equatable {
        case progress
        case success
        case warning
        case error
        case information
    }

    let title: String
    let tone: Tone
    let automaticallyClears: Bool
    let savedDestinations: [String]?

    init(
        _ title: String,
        tone: Tone,
        automaticallyClears: Bool = true,
        savedDestinations: [String]? = nil
    ) {
        self.title = title
        self.tone = tone
        self.automaticallyClears = automaticallyClears
        self.savedDestinations = savedDestinations
    }
}

final class VigilModel: ObservableObject {
    @Published private(set) var recordings: [VigilRecording] = []
    @Published private(set) var iCloudAvailability: ICloudAvailability = .checking
    @Published private(set) var uploadingIDs: Set<String> = []
    @Published private(set) var protectedIDs: Set<String> = []
    @Published private(set) var saveToCameraRoll: Bool
    @Published private(set) var cameraRollAccess: PhotoLibraryAccess = .notDetermined
    @Published private(set) var saveToICloud: Bool
    @Published private(set) var defaultRecordingMode: RecordingMode
    @Published private(set) var captureNotice: CaptureNotice?

    let googleDrive = GoogleDriveManager()

    lazy var camera: CameraController = {
        let camera = CameraController(initialMode: defaultRecordingMode)
        camera.onRecordingFinished = { [weak self] result in
            self?.recordingFinished(result)
        }
        camera.onRecordingProtectedFromInterruption = { [weak self] in
            self?.captureNotice = CaptureNotice(
                "Protecting recording…",
                tone: .progress
            )
        }
        camera.onRecordingResumedAfterInterruption = { [weak self] in
            self?.captureNotice = CaptureNotice(
                "Previous clip protected",
                tone: .success
            )
        }
        return camera
    }()

    private let cloudUploader = CloudUploader()
    private let photoLibrarySaver = PhotoLibrarySaver()
    private let protectedDefaultsKey = "protectedRecordingIDs"
    private let cameraRollDefaultsKey = "saveToCameraRoll"
    private let iCloudDefaultsKey = "saveToICloud"
    private let recordingModeDefaultsKey = "defaultRecordingMode"
    private var hasPendingQuickRecording = false
    private var hasRestoredGoogleDriveConnection = false

    init() {
        saveToCameraRoll = UserDefaults.standard.object(forKey: cameraRollDefaultsKey) as? Bool ?? false
        saveToICloud = false
        defaultRecordingMode = RecordingMode(
            rawValue: UserDefaults.standard.string(forKey: recordingModeDefaultsKey) ?? ""
        ) ?? .rear
        UserDefaults.standard.set(false, forKey: iCloudDefaultsKey)
        protectedIDs = Set(UserDefaults.standard.stringArray(forKey: protectedDefaultsKey) ?? [])
        reloadRecordings()
    }

    func start() async {
        async let cameraPreparation: Void = camera.prepare()
        async let googleDriveRestoration: Void = restoreGoogleDriveConnectionIfNeeded()
        refreshCameraRollAccess()
        await cameraPreparation
        fulfillPendingQuickRecordingIfPossible()
        await googleDriveRestoration
    }

    func requestQuickRecording() {
        guard !camera.isRecording else { return }

        hasPendingQuickRecording = true
        fulfillPendingQuickRecordingIfPossible()
    }

    func toggleRecording() {
        captureNotice = nil
        camera.isRecording ? camera.stopRecording() : camera.startRecording()
    }

    func clearCaptureNotice(_ notice: CaptureNotice) {
        guard captureNotice == notice else { return }
        captureNotice = nil
    }

    func refreshICloud() async {
        iCloudAvailability = .checking
        iCloudAvailability = await cloudUploader.availability()
    }

    func reloadRecordings() {
        recordings = RecordingFiles.load()
    }

    func setSaveToCameraRoll(_ isOn: Bool) {
        if !isOn {
            applyCameraRollPreference(false)
            return
        }

        Task {
            cameraRollAccess = await photoLibrarySaver.requestAccess()
            applyCameraRollPreference(cameraRollAccess.canSave)
            if !cameraRollAccess.canSave {
                captureNotice = CaptureNotice(
                    "Photos off · Vault remains active",
                    tone: .warning
                )
            }
        }
    }

    func setDefaultRecordingMode(_ mode: RecordingMode) {
        guard mode != .dual || camera.isDualCameraSupported else { return }
        defaultRecordingMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: recordingModeDefaultsKey)
        camera.selectMode(mode)
    }

    func delete(_ recording: VigilRecording) {
        do {
            try FileManager.default.removeItem(at: recording.url)
            protectedIDs.remove(recording.id)
            saveProtectedIDs()
            reloadRecordings()
        } catch {
            captureNotice = CaptureNotice(
                "Couldn’t delete recording",
                tone: .error
            )
        }
    }

    @discardableResult
    func upload(_ recording: VigilRecording) async -> Bool {
        guard !uploadingIDs.contains(recording.id) else { return false }
        uploadingIDs.insert(recording.id)
        defer { uploadingIDs.remove(recording.id) }

        do {
            try await cloudUploader.upload(recording)
            protectedIDs.insert(recording.id)
            saveProtectedIDs()
            iCloudAvailability = .available
            captureNotice = CaptureNotice(
                "Saved to iCloud",
                tone: .success
            )
            return true
        } catch {
            iCloudAvailability = .notConfigured(CloudUploader.friendlyMessage(for: error))
            captureNotice = CaptureNotice(
                "iCloud waiting · Safe in Vault",
                tone: .warning
            )
            return false
        }
    }

    func protectionTitle(for recording: VigilRecording) -> String {
        "Protected in Vigil Vault"
    }

    private func recordingFinished(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            reloadRecordings()
            let hasAdditionalCopies = saveToCameraRoll || googleDrive.isEnabled
            captureNotice = saveNotice(
                for: ["Vault"],
                automaticallyClears: !hasAdditionalCopies
            )
            if hasAdditionalCopies {
                Task { await saveToSelectedDestinations(recordingURL: url) }
            }
        case .failure:
            captureNotice = CaptureNotice(
                "Recording couldn’t be saved · Try again",
                tone: .error
            )
        }
    }

    private func fulfillPendingQuickRecordingIfPossible() {
        guard hasPendingQuickRecording else { return }

        switch camera.readiness {
        case .ready:
            guard !camera.isFinalizing, !camera.isChangingMode else { return }
            hasPendingQuickRecording = false
            captureNotice = nil
            camera.startRecording()
            if !camera.isRecording {
                captureNotice = CaptureNotice(
                    "Recording couldn’t start · Try again",
                    tone: .error
                )
            }
        case .denied:
            hasPendingQuickRecording = false
            captureNotice = CaptureNotice(
                "Camera access is off",
                tone: .warning
            )
        case .callInProgress:
            hasPendingQuickRecording = false
            captureNotice = CaptureNotice(
                "Video unavailable during call",
                tone: .warning
            )
        case .unavailable, .failed:
            hasPendingQuickRecording = false
            captureNotice = CaptureNotice(
                "Camera unavailable · Try again",
                tone: .error
            )
        case .idle, .requestingPermission:
            break
        }
    }

    private func restoreGoogleDriveConnectionIfNeeded() async {
        guard !hasRestoredGoogleDriveConnection else { return }
        hasRestoredGoogleDriveConnection = true
        await googleDrive.restoreConnection()
    }

    private func saveToSelectedDestinations(recordingURL: URL) async {
        var savedDestinations = ["Vault"]
        var failedDestinations: [String] = []

        if saveToCameraRoll {
            do {
                try await photoLibrarySaver.saveVideo(at: recordingURL)
                cameraRollAccess = .allowed
                savedDestinations.append("Photos")
                showSaveProgress(savedDestinations)
            } catch {
                refreshCameraRollAccess()
                failedDestinations.append("Photos")
            }
        }

        if googleDrive.isEnabled {
            let recordingID = recordingURL.deletingPathExtension().lastPathComponent
            uploadingIDs.insert(recordingID)
            do {
                try await googleDrive.uploadRecording(at: recordingURL, createdAt: Date())
                savedDestinations.append("Drive")
                showSaveProgress(savedDestinations)
            } catch {
                failedDestinations.append("Drive")
            }
            uploadingIDs.remove(recordingID)
        }

        if failedDestinations.isEmpty {
            captureNotice = saveNotice(for: savedDestinations)
        } else {
            let failedName = failedDestinations.joined(separator: " + ")
            captureNotice = CaptureNotice(
                "\(failedName) failed · \(saveStatusText(for: savedDestinations))",
                tone: .warning
            )
        }
    }

    private func showSaveProgress(_ destinations: [String]) {
        captureNotice = saveNotice(for: destinations, automaticallyClears: false)
    }

    private func saveNotice(
        for destinations: [String],
        automaticallyClears: Bool = true
    ) -> CaptureNotice {
        let orderedDestinations = orderedSaveDestinations(destinations)
        return CaptureNotice(
            saveStatusText(for: orderedDestinations),
            tone: .success,
            automaticallyClears: automaticallyClears,
            savedDestinations: orderedDestinations
        )
    }

    private func saveStatusText(for destinations: [String]) -> String {
        "Saved to \(orderedSaveDestinations(destinations).joined(separator: " + "))"
    }

    private func orderedSaveDestinations(_ destinations: [String]) -> [String] {
        ["Vault", "Drive", "Photos"].filter(destinations.contains)
    }

    private func refreshCameraRollAccess() {
        cameraRollAccess = photoLibrarySaver.currentAccess()
        if saveToCameraRoll && !cameraRollAccess.canSave {
            applyCameraRollPreference(false)
        }
    }

    private func applyCameraRollPreference(_ isOn: Bool) {
        saveToCameraRoll = isOn
        UserDefaults.standard.set(isOn, forKey: cameraRollDefaultsKey)
    }

    private func saveProtectedIDs() {
        UserDefaults.standard.set(Array(protectedIDs), forKey: protectedDefaultsKey)
    }
}
