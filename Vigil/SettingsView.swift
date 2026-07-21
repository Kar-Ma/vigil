import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: VigilModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    destinationRow(
                        icon: "photo.on.rectangle",
                        color: .blue,
                        title: "Camera Roll",
                        detail: "Add a copy to the Photos app.",
                        isOn: cameraRollBinding,
                        disabled: model.saveToCameraRoll && model.isLastEnabledDestination(.cameraRoll)
                    )

                    destinationRow(
                        icon: "lock.shield.fill",
                        color: .red,
                        title: "Vigil Vault",
                        detail: "Keep a private copy inside Vigil.",
                        isOn: vaultBinding,
                        disabled: model.saveToVault && model.isLastEnabledDestination(.vault)
                    )

                    destinationRow(
                        icon: "icloud.fill",
                        color: .cyan,
                        title: "iCloud",
                        detail: "Upload the completed recording to your private iCloud database.",
                        isOn: iCloudBinding,
                        disabled: model.saveToICloud && model.isLastEnabledDestination(.iCloud)
                    )

                    HStack(spacing: 14) {
                        destinationIcon("externaldrive.connected.to.line.below", color: .green)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text("Google Drive")
                                    .font(.body.weight(.semibold))
                                Text("COMING SOON")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.secondary.opacity(0.2), in: Capsule())
                            }
                            Text("Save a copy to a connected Google Drive account.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Google Drive", isOn: .constant(false))
                            .labelsHidden()
                            .disabled(true)
                    }
                    .opacity(0.55)
                    .padding(.vertical, 4)
                } header: {
                    Text("Save every recording to")
                } footer: {
                    Text("At least one destination must stay on. If Camera Roll or iCloud fails, Vigil keeps a local fallback copy in the Vigil Vault.")
                }

                Section("iCloud status") {
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
                }

                Section("Privacy note") {
                    Label {
                        Text("Camera Roll copies are visible in Photos. Vigil Vault copies stay inside the app and use iPhone file protection.")
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var cameraRollBinding: Binding<Bool> {
        Binding(get: { model.saveToCameraRoll }, set: { model.setSaveToCameraRoll($0) })
    }

    private var vaultBinding: Binding<Bool> {
        Binding(get: { model.saveToVault }, set: { model.setSaveToVault($0) })
    }

    private var iCloudBinding: Binding<Bool> {
        Binding(get: { model.saveToICloud }, set: { model.setSaveToICloud($0) })
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
}
