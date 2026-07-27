import AVKit
import SwiftUI

struct VaultView: View {
    @ObservedObject var model: VigilModel
    @ObservedObject var access: VaultAccessController
    @State private var selectedRecording: VigilRecording?
    @State private var recordingPendingDeletion: VigilRecording?
    @State private var cloudBackupPendingDeletion: ICloudRecordingSummary?

    var body: some View {
        Group {
            if access.isUnlocked {
                vaultContents
            } else {
                lockedVault
            }
        }
        .navigationTitle("Vigil Vault")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: access.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(access.isUnlocked ? .green : .secondary)
                    .accessibilityLabel(access.isUnlocked ? "Vault unlocked" : "Vault locked")
            }
        }
        .sheet(item: $selectedRecording) { recording in
            RecordingPlayer(recording: recording, model: model)
        }
        .onChange(of: access.isUnlocked) { _, isUnlocked in
            if !isUnlocked {
                selectedRecording = nil
                recordingPendingDeletion = nil
                cloudBackupPendingDeletion = nil
            }
        }
        .alert(
            "Delete this recording?",
            isPresented: Binding(
                get: { recordingPendingDeletion != nil },
                set: { if !$0 { recordingPendingDeletion = nil } }
            ),
            presenting: recordingPendingDeletion
        ) { recording in
            Button("Delete permanently", role: .destructive) {
                model.delete(recording)
                recordingPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                recordingPendingDeletion = nil
            }
        } message: { recording in
            if model.isBackedUpToICloud(recording) {
                Text("The copy on this iPhone will be removed. Its iCloud Drive copy will remain in Vigil › Recordings.")
            } else {
                Text("The copy on this iPhone will be removed. This cannot be undone inside Vigil.")
            }
        }
        .alert(
            "Delete this iCloud Drive copy?",
            isPresented: Binding(
                get: { cloudBackupPendingDeletion != nil },
                set: { if !$0 { cloudBackupPendingDeletion = nil } }
            ),
            presenting: cloudBackupPendingDeletion
        ) { summary in
            Button("Delete from iCloud Drive", role: .destructive) {
                Task {
                    _ = await model.deleteICloudBackup(summary)
                    cloudBackupPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                cloudBackupPendingDeletion = nil
            }
        } message: { _ in
            Text("The file will be removed from iCloud Drive › Vigil › Recordings. A copy already restored to this iPhone will remain in Vigil Vault.")
        }
    }

    private var vaultContents: some View {
        List {
            if model.recordings.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Your vault is empty",
                        systemImage: "lock.shield",
                        description: Text("Completed recordings will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Recordings") {
                    ForEach(model.recordings) { recording in
                        Button {
                            selectedRecording = recording
                        } label: {
                            RecordingRow(recording: recording, model: model)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                recordingPendingDeletion = recording
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !model.isBackedUpToICloud(recording) {
                                Button {
                                    Task {
                                        _ = await model.backupToICloud(recording)
                                    }
                                } label: {
                                    Label("Back Up", systemImage: "icloud.and.arrow.up")
                                }
                                .tint(.cyan)
                            }
                        }
                    }
                }
            }

            if model.isRefreshingICloudRecordings || !model.cloudOnlyRecordings.isEmpty {
                Section("Recover from iCloud Drive") {
                    if model.isRefreshingICloudRecordings {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Checking iCloud Drive › Vigil › Recordings…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(model.cloudOnlyRecordings) { summary in
                        Button {
                            Task {
                                _ = await model.restoreFromICloud(summary)
                            }
                        } label: {
                            ICloudRecordingRow(
                                summary: summary,
                                isRestoring: model.iCloudRestoringIDs.contains(summary.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.iCloudRestoringIDs.contains(summary.id))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                cloudBackupPendingDeletion = summary
                            } label: {
                                Label("Delete from iCloud Drive", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .refreshable {
            await model.refreshICloudBackups()
        }
        .task {
            await model.refreshICloudBackups()
        }
    }

    private var lockedVault: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.red)
            VStack(spacing: 7) {
                Text("Vigil Vault is locked")
                    .font(.title3.weight(.bold))
                Text("Use Face ID or your iPhone passcode to view, share, or manage recordings.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 36)

            Button {
                access.unlock()
            } label: {
                if access.isAuthenticating {
                    ProgressView()
                        .frame(minWidth: 128)
                } else {
                    Label("Unlock Vault", systemImage: "faceid")
                        .frame(minWidth: 128)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(access.isAuthenticating)

            if let message = access.message {
                Text(message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

private struct RecordingRow: View {
    let recording: VigilRecording
    @ObservedObject var model: VigilModel

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.red.opacity(0.16))
                    .frame(width: 52, height: 52)
                Image(systemName: "play.fill")
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.formattedDate)
                    .font(.subheadline.weight(.semibold))
                Text(recording.fileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.isBackedUpToICloud(recording) {
                    Label("Protected in Vault + iCloud Drive", systemImage: "icloud.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                } else if model.iCloudPendingIDs.contains(recording.id) {
                    Label("Vault safe · iCloud Drive waiting", systemImage: "icloud.slash")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Label(
                        model.protectionTitle(for: recording),
                        systemImage: "lock.shield.fill"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                }
            }
            Spacer()
            if model.uploadingIDs.contains(recording.id) {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ICloudRecordingRow: View {
    let summary: ICloudRecordingSummary
    let isRestoring: Bool

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.cyan.opacity(0.16))
                    .frame(width: 52, height: 52)
                Image(systemName: "icloud.and.arrow.down.fill")
                    .foregroundStyle(.cyan)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.formattedDate)
                    .font(.subheadline.weight(.semibold))
                Text(summary.formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Tap to restore to this iPhone")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
            }
            Spacer()
            if isRestoring {
                ProgressView()
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(.cyan)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RecordingPlayer: View {
    let recording: VigilRecording
    @ObservedObject var model: VigilModel
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var isShowingShareChoices = false
    @State private var isShowingShareSheet = false
    @State private var isPreparingStampedCopy = false
    @State private var sharedURL: URL?
    @State private var temporaryStampedURL: URL?
    @State private var exportErrorMessage: String?
    @State private var isShowingCloudRemovalConfirmation = false

    init(recording: VigilRecording, model: VigilModel) {
        self.recording = recording
        self.model = model
        _player = State(initialValue: AVPlayer(url: recording.url))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VideoPlayer(player: player)
                VigilPlaybackOverlay(recording: recording, player: player)

                if isPreparingStampedCopy {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Preparing Vigil-stamped copy…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(22)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
                .background(.black)
                .navigationTitle(recording.formattedDate)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button {
                            player.pause()
                            isShowingShareChoices = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isPreparingStampedCopy)

                        if model.uploadingIDs.contains(recording.id) {
                            ProgressView()
                        } else if model.isBackedUpToICloud(recording) {
                            Button {
                                isShowingCloudRemovalConfirmation = true
                            } label: {
                                Label("iCloud Drive copy saved", systemImage: "icloud.fill")
                            }
                            .tint(.cyan)
                        } else {
                            Button {
                                Task {
                                    _ = await model.backupToICloud(recording)
                                }
                            } label: {
                                Label("Back Up to iCloud Drive", systemImage: "icloud.and.arrow.up")
                            }
                            .tint(.cyan)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onAppear { player.play() }
                .onDisappear {
                    player.pause()
                    removeTemporaryStampedCopy()
                }
                .confirmationDialog(
                    "Share recording",
                    isPresented: $isShowingShareChoices,
                    titleVisibility: .visible
                ) {
                    Button("Share Original") {
                        sharedURL = recording.url
                        isShowingShareSheet = true
                    }
                    Button("Share Vigil-stamped Copy") {
                        prepareStampedCopy()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The stamped copy adds a visible Vigil mark, UTC timestamp, and recording ID. Your Vault original remains unchanged.")
                }
                .sheet(isPresented: $isShowingShareSheet, onDismiss: removeTemporaryStampedCopy) {
                    if let sharedURL {
                        ActivityShareSheet(items: [sharedURL])
                            .ignoresSafeArea()
                    }
                }
                .alert(
                    "Stamped copy unavailable",
                    isPresented: Binding(
                        get: { exportErrorMessage != nil },
                        set: { if !$0 { exportErrorMessage = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(exportErrorMessage ?? "Please try again.")
                }
                .alert(
                    "Remove the iCloud Drive copy?",
                    isPresented: $isShowingCloudRemovalConfirmation
                ) {
                    Button("Remove from iCloud Drive", role: .destructive) {
                        Task {
                            _ = await model.deleteICloudBackup(recording)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The Vault copy on this iPhone will remain. Only the file in iCloud Drive › Vigil › Recordings will be deleted.")
                }
        }
    }

    private func prepareStampedCopy() {
        guard !isPreparingStampedCopy else { return }
        isPreparingStampedCopy = true
        Task {
            do {
                let outputURL = try await VigilStampedVideoExporter.export(recording)
                temporaryStampedURL = outputURL
                sharedURL = outputURL
                isPreparingStampedCopy = false
                isShowingShareSheet = true
            } catch {
                isPreparingStampedCopy = false
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private func removeTemporaryStampedCopy() {
        if let temporaryStampedURL {
            try? FileManager.default.removeItem(at: temporaryStampedURL)
        }
        temporaryStampedURL = nil
        sharedURL = nil
    }
}
