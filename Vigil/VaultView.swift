import AVKit
import SwiftUI

struct VaultView: View {
    @ObservedObject var model: VigilModel
    @ObservedObject var access: VaultAccessController
    @State private var selectedRecording: VigilRecording?
    @State private var recordingPendingDeletion: VigilRecording?

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
            RecordingPlayer(recording: recording)
        }
        .onChange(of: access.isUnlocked) { _, isUnlocked in
            if !isUnlocked {
                selectedRecording = nil
                recordingPendingDeletion = nil
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
            Text("The copy on this iPhone will be removed. This cannot be undone inside Vigil.")
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
                    }
                }
            }
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
                Label(
                    model.protectionTitle(for: recording),
                    systemImage: "lock.shield.fill"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
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

private struct RecordingPlayer: View {
    let recording: VigilRecording
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var isShowingShareChoices = false
    @State private var isShowingShareSheet = false
    @State private var isPreparingStampedCopy = false
    @State private var sharedURL: URL?
    @State private var temporaryStampedURL: URL?
    @State private var exportErrorMessage: String?

    init(recording: VigilRecording) {
        self.recording = recording
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
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            player.pause()
                            isShowingShareChoices = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isPreparingStampedCopy)
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
