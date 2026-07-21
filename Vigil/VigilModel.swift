import Combine
import Foundation

final class VigilModel: ObservableObject {
    @Published private(set) var recordings: [VigilRecording] = []
    @Published private(set) var iCloudAvailability: ICloudAvailability = .checking
    @Published private(set) var uploadingIDs: Set<String> = []
    @Published private(set) var protectedIDs: Set<String> = []
    @Published private(set) var saveToCameraRoll: Bool
    @Published private(set) var cameraRollAccess: PhotoLibraryAccess = .notDetermined
    @Published private(set) var saveToICloud: Bool
    @Published private(set) var defaultRecordingMode: RecordingMode
    @Published var bannerMessage: String?

    let googleDrive = GoogleDriveManager()

    lazy var camera: CameraController = {
        let camera = CameraController(initialMode: defaultRecordingMode)
        camera.onRecordingFinished = { [weak self] result in
            self?.recordingFinished(result)
        }
        camera.onRecordingProtectedFromInterruption = { [weak self] in
            self?.bannerMessage = "Interruption detected. Protecting the current recording."
        }
        camera.onRecordingResumedAfterInterruption = { [weak self] in
            self?.bannerMessage = "Recording resumed in a new protected clip."
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
        guard !camera.isRecording else {
            bannerMessage = "Vigil is already recording."
            return
        }

        hasPendingQuickRecording = true
        fulfillPendingQuickRecordingIfPossible()
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
                bannerMessage = "Allow Photos access in iPhone Settings to save Camera Roll copies."
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
            bannerMessage = "This recording could not be deleted."
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
            bannerMessage = "Recording protected in iCloud."
            return true
        } catch {
            iCloudAvailability = .notConfigured(CloudUploader.friendlyMessage(for: error))
            bannerMessage = "Saved on this iPhone. iCloud upload is waiting for setup."
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
            bannerMessage = "Recording saved to your private vault."
            Task { await saveToSelectedDestinations(recordingURL: url) }
        case .failure:
            bannerMessage = "Recording could not be saved. Please try again."
        }
    }

    private func fulfillPendingQuickRecordingIfPossible() {
        guard hasPendingQuickRecording else { return }

        switch camera.readiness {
        case .ready:
            guard !camera.isFinalizing, !camera.isChangingMode else { return }
            hasPendingQuickRecording = false
            camera.startRecording()
            if camera.isRecording {
                bannerMessage = "Recording started from Quick Access."
            } else {
                bannerMessage = "Recording could not start. Please tap the record button."
            }
        case .denied:
            hasPendingQuickRecording = false
            bannerMessage = "Allow camera and microphone access before using Quick Access."
        case .callInProgress:
            hasPendingQuickRecording = false
            bannerMessage = "Recording video is not available while on a call."
        case .unavailable, .failed:
            hasPendingQuickRecording = false
            bannerMessage = "The camera is not available for Quick Access right now."
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
        var savedDestinations = ["Vigil Vault"]
        var failedDestinations: [String] = []

        if saveToCameraRoll {
            do {
                try await photoLibrarySaver.saveVideo(at: recordingURL)
                cameraRollAccess = .allowed
                savedDestinations.append("Camera Roll")
            } catch {
                refreshCameraRollAccess()
                failedDestinations.append("Camera Roll")
            }
        }

        if googleDrive.isEnabled {
            let recordingID = recordingURL.deletingPathExtension().lastPathComponent
            uploadingIDs.insert(recordingID)
            do {
                try await googleDrive.uploadRecording(at: recordingURL, createdAt: Date())
                savedDestinations.append("Google Drive")
            } catch {
                failedDestinations.append("Google Drive")
            }
            uploadingIDs.remove(recordingID)
        }

        if failedDestinations.isEmpty {
            bannerMessage = "Saved to \(savedDestinations.joined(separator: " and "))."
        } else {
            bannerMessage = "\(failedDestinations.joined(separator: " and ")) save failed. The Vigil Vault copy is safe."
        }
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
