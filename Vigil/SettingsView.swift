import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var model: VigilModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    destinationRow(
                        icon: "photo.on.rectangle",
                        color: .blue,
                        title: "Camera Roll",
                        detail: model.cameraRollAccess.detail,
                        isOn: cameraRollBinding,
                        disabled: model.cameraRollAccess == .restricted
                    )

                    alwaysOnRow(
                        icon: "lock.shield.fill",
                        color: .red,
                        title: "Vigil Vault",
                        detail: "Every recording is always protected inside Vigil."
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

                    comingSoonRow(
                        icon: "externaldrive.connected.to.line.below",
                        color: .green,
                        title: "Google Drive",
                        detail: "Save a copy to a connected Google Drive account."
                    )
                } header: {
                    Text("Save every recording to")
                } footer: {
                    Text("Vigil Vault is always on. Camera Roll and future cloud options create additional copies; they never replace the protected Vault recording.")
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
