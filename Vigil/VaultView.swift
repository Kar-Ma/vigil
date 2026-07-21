import AVKit
import SwiftUI

struct VaultView: View {
    @ObservedObject var model: VigilModel
    @State private var selectedRecording: VigilRecording?
    @State private var recordingPendingDeletion: VigilRecording?

    var body: some View {
        NavigationStack {
            List {
                iCloudSection

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
                                if !model.protectedIDs.contains(recording.id) {
                                    Button {
                                        Task { await model.upload(recording) }
                                    } label: {
                                        Label("Protect", systemImage: "icloud.and.arrow.up")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .refreshable {
                await model.refreshICloud()
            }
            .navigationTitle("Private Vault")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Private local storage")
                }
            }
        }
        .sheet(item: $selectedRecording) { recording in
            RecordingPlayer(recording: recording)
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

    private var iCloudSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.iCloudAvailability == .available ? "checkmark.icloud.fill" : "icloud.slash")
                    .font(.title2)
                    .foregroundStyle(model.iCloudAvailability == .available ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.iCloudAvailability.title)
                        .font(.headline)
                    Text(model.iCloudAvailability.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if model.iCloudAvailability != .available {
                    Button("Retry") {
                        Task { await model.refreshICloud() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.iCloudAvailability == .checking)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Protection")
        }
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
                    systemImage: model.protectedIDs.contains(recording.id) ? "checkmark.icloud" : "iphone"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(model.protectedIDs.contains(recording.id) ? .green : .orange)
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

    init(recording: VigilRecording) {
        self.recording = recording
        _player = State(initialValue: AVPlayer(url: recording.url))
    }

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .background(.black)
                .navigationTitle(recording.formattedDate)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onAppear { player.play() }
                .onDisappear { player.pause() }
        }
    }
}
