import Combine
import Foundation

final class VigilModel: ObservableObject {
    @Published private(set) var recordings: [VigilRecording] = []
    @Published private(set) var iCloudAvailability: ICloudAvailability = .checking
    @Published private(set) var uploadingIDs: Set<String> = []
    @Published private(set) var protectedIDs: Set<String> = []
    @Published private(set) var saveToCameraRoll: Bool
    @Published private(set) var cameraRollAccess: PhotoLibraryAccess = .notDetermined
    @Published private(set) var cameraRollLastResult: String?
    @Published private(set) var cameraRollLastSaveSucceeded = false
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
    private let iCloudDefaultsKey = "saveToICloud"

    init() {
        saveToCameraRoll = UserDefaults.standard.object(forKey: cameraRollDefaultsKey) as? Bool ?? false
        saveToICloud = false
        UserDefaults.standard.set(false, forKey: iCloudDefaultsKey)
        protectedIDs = Set(UserDefaults.standard.stringArray(forKey: protectedDefaultsKey) ?? [])
        reloadRecordings()
    }

    func start() async {
        async let cameraPreparation: Void = camera.prepare()
        refreshCameraRollAccess()
        await cameraPreparation
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
            cameraRollLastResult = nil
            return
        }

        Task {
            cameraRollAccess = await photoLibrarySaver.requestAccess()
            applyCameraRollPreference(cameraRollAccess.canSave)
            if cameraRollAccess.canSave {
                cameraRollLastSaveSucceeded = true
                cameraRollLastResult = "Photos permission granted. Your next recording will also be saved there."
            } else {
                cameraRollLastSaveSucceeded = false
                cameraRollLastResult = "Photos permission is off, so Camera Roll copies cannot be saved."
                bannerMessage = "Allow Photos access in iPhone Settings to save Camera Roll copies."
            }
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
        var savedDestinations = ["Vigil Vault"]

        if saveToCameraRoll {
            do {
                try await photoLibrarySaver.saveVideo(at: recording.url)
                cameraRollAccess = .allowed
                cameraRollLastSaveSucceeded = true
                cameraRollLastResult = "Last Camera Roll copy saved successfully."
                savedDestinations.append("Camera Roll")
            } catch {
                refreshCameraRollAccess()
                cameraRollLastSaveSucceeded = false
                cameraRollLastResult = "Last Camera Roll save failed: \(error.localizedDescription)"
                bannerMessage = "Camera Roll save failed: \(error.localizedDescription) The Vigil Vault copy is safe."
                return
            }
        }

        bannerMessage = "Saved to \(savedDestinations.joined(separator: " and "))."
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
