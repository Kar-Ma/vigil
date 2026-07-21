import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var model: VigilModel
    @ObservedObject var vaultAccess: VaultAccessController
    @ObservedObject var googleDrive: GoogleDriveManager
    @ObservedObject var screenCurtain: ScreenCurtainController
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingVault = false
    @State private var isWaitingToOpenVault = false
    @State private var isShowingActionButtonSetup = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        openVault()
                    } label: {
                        alwaysOnRow(
                            icon: "lock.shield.fill",
                            color: .red,
                            title: "Vigil Vault",
                            detail: "Every recording is always protected inside Vigil."
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(vaultAccess.isAuthenticating)

                    destinationRow(
                        icon: "photo.on.rectangle",
                        color: .blue,
                        title: "Camera Roll",
                        detail: model.cameraRollAccess.detail,
                        isOn: cameraRollBinding,
                        disabled: model.cameraRollAccess == .restricted
                    )

                    if model.cameraRollAccess == .denied {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        } label: {
                            Label("Open iPhone Settings for Photos", systemImage: "gear")
                        }
                    }

                    googleDriveRow

                    comingSoonRow(
                        icon: "icloud.fill",
                        color: .cyan,
                        title: "iCloud",
                        detail: "Save a copy to your private iCloud storage."
                    )
                } header: {
                    Text("Save every recording to")
                }

                Section {
                    ForEach(RecordingMode.allCases) { mode in
                        recordingModeRow(mode)
                    }
                } header: {
                    Text("Default recording mode")
                }

                Section {
                    HStack(spacing: 14) {
                        destinationIcon("rectangle.fill.on.rectangle.fill", color: .indigo)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Screen Curtain gesture")
                                .font(.body.weight(.semibold))
                            Text("Three-finger triple-tap on Record to hide the live preview and dim the display.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Screen Curtain gesture", isOn: screenCurtainBinding)
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Privacy controls")
                }

                Section {
                    Button {
                        isShowingActionButtonSetup = true
                    } label: {
                        HStack(spacing: 14) {
                            destinationIcon("button.programmable", color: .orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Action Button")
                                    .font(.body.weight(.semibold))
                                Text("Set it to open Vigil and start recording.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Quick access")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $isShowingVault) {
                VaultView(model: model, access: vaultAccess)
            }
            .alert("Set up the Action Button", isPresented: $isShowingActionButtonSetup) {
                Button("Done", role: .cancel) {}
            } message: {
                Text("Open iPhone Settings → Action Button. Swipe to Shortcut, tap Choose a Shortcut, then select “Start Vigil Recording.”")
            }
        }
        .onChange(of: vaultAccess.isUnlocked) { _, isUnlocked in
            guard isWaitingToOpenVault, isUnlocked else { return }
            isWaitingToOpenVault = false
            isShowingVault = true
        }
        .onChange(of: vaultAccess.isAuthenticating) { wasAuthenticating, isAuthenticating in
            if wasAuthenticating, !isAuthenticating, !vaultAccess.isUnlocked {
                isWaitingToOpenVault = false
            }
        }
        .onChange(of: isShowingVault) { wasShowing, isShowing in
            if wasShowing, !isShowing {
                vaultAccess.lock()
            }
        }
    }

    private func openVault() {
        if vaultAccess.isUnlocked {
            isShowingVault = true
        } else {
            isWaitingToOpenVault = true
            vaultAccess.unlock()
        }
    }

    private var cameraRollBinding: Binding<Bool> {
        Binding(get: { model.saveToCameraRoll }, set: { model.setSaveToCameraRoll($0) })
    }

    private var googleDriveBinding: Binding<Bool> {
        Binding(get: { googleDrive.isEnabled }, set: { googleDrive.setEnabled($0) })
    }

    private var screenCurtainBinding: Binding<Bool> {
        Binding(
            get: { screenCurtain.isGestureEnabled },
            set: { screenCurtain.setGestureEnabled($0) }
        )
    }

    private func recordingModeRow(_ mode: RecordingMode) -> some View {
        let isUnavailable = mode == .dual && !model.camera.isDualCameraSupported

        return Button {
            model.setDefaultRecordingMode(mode)
        } label: {
            HStack(spacing: 14) {
                destinationIcon(mode.systemImage, color: mode == .dual ? .purple : .blue)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(mode.title)
                            .font(.body.weight(.semibold))
                        if mode == .rear {
                            Text("RECOMMENDED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.green.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(isUnavailable ? "Not supported on this iPhone." : mode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.defaultRecordingMode == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable || model.camera.isRecording)
        .opacity(isUnavailable ? 0.5 : 1)
    }

    private func destinationRow(
        icon: String,
        color: Color,
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        disabled: Bool
    ) -> some View {
        HStack(spacing: 14) {
            destinationIcon(icon, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .disabled(disabled)
        }
        .padding(.vertical, 4)
    }

    private var googleDriveRow: some View {
        HStack(spacing: 14) {
            destinationIcon("externaldrive.connected.to.line.below", color: .green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Google Drive")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let accountEmail = googleDrive.accountEmail {
                    Button {
                        googleDrive.openVigilFolder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(accountEmail)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if googleDrive.isOpeningFolder {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(googleDrive.isOpeningFolder)
                    .accessibilityLabel("Open Vigil folder in Google Drive")
                } else {
                    Text(googleDriveDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Toggle("Google Drive", isOn: googleDriveBinding)
                .labelsHidden()
                .disabled(googleDrive.isConnecting)
        }
        .padding(.vertical, 4)
    }

    private var googleDriveDetail: String {
        if googleDrive.isConnecting {
            return "Connecting…"
        }
        if googleDrive.activeUploadCount > 0 {
            return "Uploading to Google Drive…"
        }
        if let accountEmail = googleDrive.accountEmail {
            return accountEmail
        }
        if let error = googleDrive.lastErrorMessage {
            return error
        }
        return "Save a copy to a Vigil folder."
    }

    private func destinationIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.title3.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
    }

    private func alwaysOnRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            destinationIcon(icon, color: color)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text("ALWAYS ON")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.14), in: Capsule())
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }

    private func comingSoonRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            destinationIcon(icon, color: color)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text("COMING SOON")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.2), in: Capsule())
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: .constant(false))
                .labelsHidden()
                .disabled(true)
        }
        .opacity(0.55)
        .padding(.vertical, 4)
    }
}
