import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var model: VigilModel
    @ObservedObject var vaultAccess: VaultAccessController
    @ObservedObject var googleDrive: GoogleDriveManager
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingVault = false
    @State private var isWaitingToOpenVault = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RecordingMode.allCases) { mode in
                        recordingModeRow(mode)
                    }
                } header: {
                    Text("Default recording mode")
                } footer: {
                    Text("You can temporarily change the mode on the Record screen before recording begins. Rear Camera is the most reliable and uses less power.")
                }

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

                    comingSoonRow(
                        icon: "icloud.fill",
                        color: .cyan,
                        title: "iCloud",
                        detail: "Protect a copy in your private iCloud storage."
                    )

                    destinationRow(
                        icon: "externaldrive.connected.to.line.below",
                        color: .green,
                        title: "Google Drive",
                        detail: googleDrive.statusDetail,
                        isOn: googleDriveBinding,
                        disabled: googleDrive.isConnecting
                    )
                } header: {
                    Text("Save every recording to")
                } footer: {
                    Text("Vigil Vault is always on. Camera Roll and Google Drive create additional copies; they never replace the protected Vault recording.")
                }

                Section("Privacy note") {
                    Label {
                        Text("Camera Roll copies are visible in Photos. Google Drive copies are sent to the connected account. Vigil Vault copies stay inside the app and use iPhone file protection.")
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.orange)
                    }
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
