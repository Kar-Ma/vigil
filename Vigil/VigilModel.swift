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
    @Published private(set) var iCloudBackedUpIDs: Set<String> = []
    @Published private(set) var iCloudPendingIDs: Set<String> = []
    @Published private(set) var iCloudRecordings: [ICloudRecordingSummary] = []
    @Published private(set) var iCloudRestoringIDs: Set<String> = []
    @Published private(set) var isRefreshingICloudRecordings = false
    @Published private(set) var iCloudLastErrorMessage: String?
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
    private let iCloudBackedUpDefaultsKey = "iCloudDriveBackedUpRecordingIDs"
    private let iCloudPendingDefaultsKey = "pendingICloudDriveRecordingIDs"
    private let cameraRollDefaultsKey = "saveToCameraRoll"
    private let iCloudDefaultsKey = "saveToICloud"
    private let recordingModeDefaultsKey = "defaultRecordingMode"
    private var hasPendingQuickRecording = false
    private var hasRestoredGoogleDriveConnection = false
    private var iCloudProcessingTask: Task<Void, Never>?

    init() {
        saveToCameraRoll = UserDefaults.standard.object(forKey: cameraRollDefaultsKey) as? Bool ?? false
        saveToICloud = UserDefaults.standard.object(forKey: iCloudDefaultsKey) as? Bool ?? false
        defaultRecordingMode = RecordingMode(
            rawValue: UserDefaults.standard.string(forKey: recordingModeDefaultsKey) ?? ""
        ) ?? .rear
        iCloudBackedUpIDs = Set(
            UserDefaults.standard.stringArray(forKey: iCloudBackedUpDefaultsKey) ?? []
        )
        iCloudPendingIDs = Set(
            UserDefaults.standard.stringArray(forKey: iCloudPendingDefaultsKey) ?? []
        )
        reloadRecordings()
    }

    func start() async {
        async let cameraPreparation: Void = camera.prepare()
        async let googleDriveRestoration: Void = restoreGoogleDriveConnectionIfNeeded()
        async let iCloudPreparation: Void = prepareICloud()
        refreshCameraRollAccess()
        await cameraPreparation
        fulfillPendingQuickRecordingIfPossible()
        await googleDriveRestoration
        await iCloudPreparation
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
        if iCloudAvailability.canUpload {
            iCloudLastErrorMessage = nil
            await processICloudQueue()
        }
    }

    func setSaveToICloud(_ isOn: Bool) {
        guard isOn else {
            applyICloudPreference(false)
            captureNotice = CaptureNotice(
                "Automatic iCloud Drive backup off",
                tone: .information
            )
            return
        }

        Task {
            await refreshICloud()
            guard iCloudAvailability.canUpload else {
                applyICloudPreference(false)
                captureNotice = CaptureNotice(
                    iCloudAvailability.title,
                    tone: .warning
                )
                return
            }

            applyICloudPreference(true)
            captureNotice = CaptureNotice(
                "iCloud Drive ready for new recordings",
                tone: .success
            )
        }
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
            iCloudPendingIDs.remove(recording.id)
            saveICloudState()
            reloadRecordings()
        } catch {
            captureNotice = CaptureNotice(
                "Couldn’t delete recording",
                tone: .error
            )
        }
    }

    @discardableResult
    func backupToICloud(_ recording: VigilRecording) async -> Bool {
        let didBackUp = await queueICloudBackup(recording)
        if didBackUp {
            captureNotice = CaptureNotice("Saved to iCloud Drive", tone: .success)
        } else {
            captureNotice = CaptureNotice(
                "iCloud Drive waiting · Safe in Vault",
                tone: .warning
            )
        }
        return didBackUp
    }

    func refreshICloudBackups() async {
        guard !isRefreshingICloudRecordings else { return }

        if !iCloudAvailability.canUpload {
            await refreshICloud()
        }
        guard iCloudAvailability.canUpload else { return }

        isRefreshingICloudRecordings = true
        defer { isRefreshingICloudRecordings = false }

        do {
            let summaries = try await cloudUploader.listRecordings()
                .filter(\.isUploaded)
            iCloudRecordings = summaries
            iCloudBackedUpIDs.formUnion(summaries.map(\.id))
            iCloudLastErrorMessage = nil
            saveICloudState()
        } catch {
            iCloudLastErrorMessage = CloudUploader.friendlyMessage(for: error)
        }
    }

    @discardableResult
    func restoreFromICloud(_ summary: ICloudRecordingSummary) async -> Bool {
        guard !iCloudRestoringIDs.contains(summary.id) else { return false }
        iCloudRestoringIDs.insert(summary.id)
        defer { iCloudRestoringIDs.remove(summary.id) }

        do {
            let iCloudDriveURL = try await cloudUploader.downloadedURL(for: summary)
            _ = try RecordingFiles.restore(
                cloudAssetAt: iCloudDriveURL,
                filename: summary.filename,
                createdAt: summary.createdAt
            )
            iCloudBackedUpIDs.insert(summary.id)
            saveICloudState()
            reloadRecordings()
            captureNotice = CaptureNotice(
                "Restored to Vigil Vault",
                tone: .success
            )
            return true
        } catch {
            iCloudLastErrorMessage = CloudUploader.friendlyMessage(for: error)
            captureNotice = CaptureNotice(
                "iCloud Drive restore couldn’t finish",
                tone: .warning
            )
            return false
        }
    }

    func deleteICloudBackup(_ summary: ICloudRecordingSummary) async -> Bool {
        await deleteICloudBackup(recordingID: summary.id)
    }

    func deleteICloudBackup(_ recording: VigilRecording) async -> Bool {
        await deleteICloudBackup(recordingID: recording.id)
    }

    private func deleteICloudBackup(recordingID: String) async -> Bool {
        do {
            try await cloudUploader.delete(recordingID: recordingID)
            iCloudRecordings.removeAll { $0.id == recordingID }
            iCloudBackedUpIDs.remove(recordingID)
            iCloudPendingIDs.remove(recordingID)
            saveICloudState()
            captureNotice = CaptureNotice(
                "Removed from iCloud Drive",
                tone: .success
            )
            return true
        } catch {
            iCloudLastErrorMessage = CloudUploader.friendlyMessage(for: error)
            captureNotice = CaptureNotice(
                "Couldn’t remove iCloud Drive backup",
                tone: .warning
            )
            return false
        }
    }

    func protectionTitle(for recording: VigilRecording) -> String {
        "Protected in Vigil Vault"
    }

    func isBackedUpToICloud(_ recording: VigilRecording) -> Bool {
        iCloudBackedUpIDs.contains(recording.id)
    }

    var cloudOnlyRecordings: [ICloudRecordingSummary] {
        let localIDs = Set(recordings.map(\.id))
        return iCloudRecordings.filter { !localIDs.contains($0.id) }
    }

    private func recordingFinished(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            reloadRecordings()
            let recordingID = url.deletingPathExtension().lastPathComponent
            let recording = recordings.first(where: { $0.id == recordingID })
                ?? VigilRecording(url: url, createdAt: Date())
            let hasAdditionalCopies = saveToCameraRoll || googleDrive.isEnabled || saveToICloud
            captureNotice = saveNotice(
                for: ["Vault"],
                automaticallyClears: !hasAdditionalCopies
            )
            if hasAdditionalCopies {
                Task { await saveToSelectedDestinations(recording: recording) }
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

    private func prepareICloud() async {
        iCloudAvailability = await cloudUploader.availability()
        guard iCloudAvailability.canUpload else { return }
        iCloudLastErrorMessage = nil
        await processICloudQueue()
    }

    private func saveToSelectedDestinations(recording: VigilRecording) async {
        var savedDestinations = ["Vault"]
        var failedDestinations: [String] = []

        if saveToCameraRoll {
            do {
                try await photoLibrarySaver.saveVideo(at: recording.url)
                cameraRollAccess = .allowed
                savedDestinations.append("Photos")
                showSaveProgress(savedDestinations)
            } catch {
                refreshCameraRollAccess()
                failedDestinations.append("Photos")
            }
        }

        if googleDrive.isEnabled {
            uploadingIDs.insert(recording.id)
            do {
                try await googleDrive.uploadRecording(
                    at: recording.url,
                    createdAt: recording.createdAt
                )
                savedDestinations.append("Drive")
                showSaveProgress(savedDestinations)
            } catch {
                failedDestinations.append("Drive")
            }
            uploadingIDs.remove(recording.id)
        }

        if saveToICloud {
            showICloudSyncing(savedDestinations)
            if await queueICloudBackup(recording) {
                savedDestinations.append("iCloud")
                showSaveProgress(savedDestinations)
            } else {
                failedDestinations.append("iCloud")
            }
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

    private func showICloudSyncing(_ destinations: [String]) {
        let orderedDestinations = orderedSaveDestinations(destinations)
        captureNotice = CaptureNotice(
            "\(saveStatusText(for: orderedDestinations)) · iCloud Drive syncing",
            tone: .progress,
            automaticallyClears: false,
            savedDestinations: orderedDestinations
        )
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
        ["Vault", "iCloud", "Drive", "Photos"].filter(destinations.contains)
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

    private func applyICloudPreference(_ isOn: Bool) {
        saveToICloud = isOn
        UserDefaults.standard.set(isOn, forKey: iCloudDefaultsKey)
    }

    private func queueICloudBackup(_ recording: VigilRecording) async -> Bool {
        if iCloudBackedUpIDs.contains(recording.id) {
            return true
        }

        iCloudPendingIDs.insert(recording.id)
        saveICloudState()

        if !iCloudAvailability.canUpload {
            iCloudAvailability = await cloudUploader.availability()
        }
        guard iCloudAvailability.canUpload else {
            return false
        }

        await processICloudQueue()
        return iCloudBackedUpIDs.contains(recording.id)
    }

    private func processICloudQueue() async {
        guard iCloudAvailability.canUpload, !iCloudPendingIDs.isEmpty else { return }

        if let iCloudProcessingTask {
            await iCloudProcessingTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.drainICloudQueue()
        }
        iCloudProcessingTask = task
        await task.value
        iCloudProcessingTask = nil
    }

    private func drainICloudQueue() async {
        let localRecordingIDs = Set(recordings.map(\.id))
        iCloudPendingIDs.formIntersection(localRecordingIDs)
        saveICloudState()

        while let recording = recordings
            .filter({ iCloudPendingIDs.contains($0.id) })
            .min(by: { $0.createdAt < $1.createdAt }) {
            uploadingIDs.insert(recording.id)

            do {
                try await cloudUploader.upload(
                    filename: recording.filename,
                    fileURL: recording.url,
                    fileSize: recording.fileSizeInBytes
                )
                uploadingIDs.remove(recording.id)
                iCloudPendingIDs.remove(recording.id)
                iCloudBackedUpIDs.insert(recording.id)
                iCloudLastErrorMessage = nil
                saveICloudState()
            } catch {
                uploadingIDs.remove(recording.id)
                iCloudLastErrorMessage = CloudUploader.friendlyMessage(for: error)
                iCloudAvailability = await cloudUploader.availability()
                saveICloudState()
                break
            }
        }
    }

    private func saveICloudState() {
        UserDefaults.standard.set(
            Array(iCloudBackedUpIDs),
            forKey: iCloudBackedUpDefaultsKey
        )
        UserDefaults.standard.set(
            Array(iCloudPendingIDs),
            forKey: iCloudPendingDefaultsKey
        )
    }
}
