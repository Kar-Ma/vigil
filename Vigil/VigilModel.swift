import Combine
import Foundation

final class VigilModel: ObservableObject {
    enum Destination {
        case cameraRoll
        case vault
    }

    @Published private(set) var recordings: [VigilRecording] = []
    @Published private(set) var iCloudAvailability: ICloudAvailability = .checking
    @Published private(set) var uploadingIDs: Set<String> = []
    @Published private(set) var protectedIDs: Set<String> = []
    @Published private(set) var saveToCameraRoll: Bool
    @Published private(set) var saveToVault: Bool
    @Published private(set) var saveToICloud: Bool
    @Published var bannerMessage: String?

    lazy var camera: CameraController = {
        let camera = CameraController()
        camera.onRecordingFinished = { [weak self] result in
            self?.recordingFinished(result)
        }
        return camera
    }()

    private let cloudUploader = CloudUploader()
    private let photoLibrarySaver = PhotoLibrarySaver()
    private let protectedDefaultsKey = "protectedRecordingIDs"
    private let cameraRollDefaultsKey = "saveToCameraRoll"
    private let vaultDefaultsKey = "saveToVault"
    private let iCloudDefaultsKey = "saveToICloud"

    init() {
        saveToCameraRoll = UserDefaults.standard.object(forKey: cameraRollDefaultsKey) as? Bool ?? false
        saveToVault = UserDefaults.standard.object(forKey: vaultDefaultsKey) as? Bool ?? true
        saveToICloud = false
        UserDefaults.standard.set(false, forKey: iCloudDefaultsKey)
        protectedIDs = Set(UserDefaults.standard.stringArray(forKey: protectedDefaultsKey) ?? [])
        reloadRecordings()
    }

    func start() async {
        await camera.prepare()
    }

    func refreshICloud() async {
        iCloudAvailability = .checking
        iCloudAvailability = await cloudUploader.availability()
    }

    func reloadRecordings() {
        recordings = RecordingFiles.load()
    }

    func setSaveToCameraRoll(_ isOn: Bool) {
        guard isOn || !isLastEnabledDestination(.cameraRoll) else { return }
        saveToCameraRoll = isOn
        UserDefaults.standard.set(isOn, forKey: cameraRollDefaultsKey)
    }

    func setSaveToVault(_ isOn: Bool) {
        guard isOn || !isLastEnabledDestination(.vault) else { return }
        saveToVault = isOn
        UserDefaults.standard.set(isOn, forKey: vaultDefaultsKey)
    }

    func isLastEnabledDestination(_ destination: Destination) -> Bool {
        let enabledCount = [saveToCameraRoll, saveToVault].filter { $0 }.count
        guard enabledCount == 1 else { return false }
        switch destination {
        case .cameraRoll: return saveToCameraRoll
        case .vault: return saveToVault
        }
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
            guard let recording = recordings.first(where: { $0.url == url }) else { return }
            bannerMessage = "Recording saved to your private vault."
            Task { await saveToSelectedDestinations(recording) }
        case .failure:
            bannerMessage = "Recording could not be saved. Please try again."
        }
    }

    private func saveToSelectedDestinations(_ recording: VigilRecording) async {
        var allRequestedExternalSavesSucceeded = true
        var savedDestinations: [String] = []

        if saveToVault {
            savedDestinations.append("Vigil Vault")
        }

        if saveToCameraRoll {
            do {
                try await photoLibrarySaver.saveVideo(at: recording.url)
                savedDestinations.append("Camera Roll")
            } catch {
                allRequestedExternalSavesSucceeded = false
                bannerMessage = "Camera Roll save failed. A fallback copy is safe in Vigil Vault."
            }
        }

        if !saveToVault && allRequestedExternalSavesSucceeded && !savedDestinations.isEmpty {
            try? FileManager.default.removeItem(at: recording.url)
            reloadRecordings()
        }

        if allRequestedExternalSavesSucceeded {
            bannerMessage = "Saved to \(savedDestinations.joined(separator: " and "))."
        }
    }

    private func saveProtectedIDs() {
        UserDefaults.standard.set(Array(protectedIDs), forKey: protectedDefaultsKey)
    }
}
