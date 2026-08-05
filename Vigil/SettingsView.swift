import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var model: VigilModel
    @ObservedObject var vaultAccess: VaultAccessController
    @ObservedObject var googleDrive: GoogleDriveManager
    @ObservedObject var screenCurtain: ScreenCurtainController
    @AppStorage(EmergencyCallHandoff.defaultsKey)
    private var emergencyNumber = EmergencyCallHandoff.defaultNumber
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingVault = false
    @State private var isWaitingToOpenVault = false
    @State private var isShowingActionButtonSetup = false
    @State private var isShowingICloudSetup = false
    @State private var isRecheckingICloud = false
    @State private var didICloudRecheckFail = false
    @State private var isShowingGoogleDriveAccount = false
    @State private var isConfirmingGoogleDisconnect = false
    @State private var isShowingEmergencyNumberEditor = false
    @State private var draftEmergencyNumber = ""
    @State private var iCloudRecheckTask: Task<Void, Never>?

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
                            detail: "Save securely in Vigil."
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(vaultAccess.isAuthenticating)

                    destinationRow(
                        icon: "photo.on.rectangle",
                        color: .blue,
                        title: "Camera Roll",
                        detail: "Save a copy to Photos.",
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

                    iCloudRow
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

                Section {
                    Button {
                        draftEmergencyNumber = emergencyNumber
                        isShowingEmergencyNumberEditor = true
                    } label: {
                        HStack(spacing: 14) {
                            destinationIcon("cross.case.fill", color: .red)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("SOS number")
                                    .font(.body.weight(.semibold))
                                Text("Emergency number for your region.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(emergencyNumber.isEmpty ? "Not set" : emergencyNumber)
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Emergency")
                } footer: {
                    Text("Vigil opens the iPhone call confirmation. Verify the correct emergency number for your location.")
                }

                Section {
                    externalLinkRow(
                        title: "Privacy Policy",
                        icon: "hand.raised.fill",
                        urlString: "https://keep-vigil.vercel.app/privacy"
                    )
                    externalLinkRow(
                        title: "Help & Support",
                        icon: "questionmark.circle.fill",
                        urlString: "https://keep-vigil.vercel.app/support"
                    )
                } header: {
                    Text("About")
                } footer: {
                    Text("Vigil \(appVersion)")
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
            .sheet(isPresented: $isShowingICloudSetup) {
                iCloudSetupSheet
            }
            .sheet(isPresented: $isShowingGoogleDriveAccount) {
                googleDriveAccountSheet
            }
            .sheet(isPresented: $isShowingEmergencyNumberEditor) {
                emergencyNumberEditor
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
        .onChange(of: isShowingICloudSetup) { _, isShowing in
            if !isShowing {
                cancelICloudRecheck()
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

    private var iCloudBinding: Binding<Bool> {
        Binding(
            get: { model.saveToICloud },
            set: { isOn in
                Task {
                    let didApply = await model.setSaveToICloud(isOn)
                    if isOn && !didApply {
                        didICloudRecheckFail = false
                        isShowingICloudSetup = true
                    }
                }
            }
        )
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
            if googleDrive.accountEmail != nil {
                Button {
                    isShowingGoogleDriveAccount = true
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text("Google Drive")
                                .font(.body.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        Text("Save a copy to Google Drive.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manage the connected Google Drive account")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Google Drive")
                        .font(.body.weight(.semibold))
                    Text("Save a copy to Google Drive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("Google Drive", isOn: googleDriveBinding)
                .labelsHidden()
                .disabled(googleDrive.isConnecting)
        }
        .padding(.vertical, 4)
    }

    private var googleDriveAccountSheet: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Connected account") {
                        Text(googleDrive.accountEmail ?? "Google Drive")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Button {
                        googleDrive.openVigilFolder()
                    } label: {
                        Label("Open Vigil Folder", systemImage: "folder.fill")
                    }
                    .disabled(googleDrive.isOpeningFolder)
                } footer: {
                    Text("Turning uploads off keeps this connection. Disconnecting removes Google access from Vigil on this iPhone.")
                }

                Section {
                    Button("Disconnect Google Drive", role: .destructive) {
                        isConfirmingGoogleDisconnect = true
                    }
                }
            }
            .navigationTitle("Google Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isShowingGoogleDriveAccount = false
                    }
                }
            }
            .alert("Disconnect Google Drive?", isPresented: $isConfirmingGoogleDisconnect) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    googleDrive.disconnect()
                    isShowingGoogleDriveAccount = false
                }
            } message: {
                Text("New recordings will stop uploading. Files already saved in Google Drive will not be deleted.")
            }
        }
        .presentationDetents([.medium])
    }

    private var iCloudRow: some View {
        HStack(spacing: 14) {
            destinationIcon("icloud.fill", color: .cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text("iCloud Drive")
                    .font(.body.weight(.semibold))
                Text("Save a copy to iCloud Drive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("iCloud Drive", isOn: iCloudBinding)
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .task {
            await model.refreshICloud()
        }
    }

    private var iCloudSetupSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 82, height: 82)
                        .background(.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 22))

                    VStack(spacing: 8) {
                        Text("Set up iCloud Drive")
                            .font(.title2.bold())

                        Text("Turn on iCloud Drive syncing so Vigil can save recordings you can access from another device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        iCloudSetupStep(
                            number: 1,
                            title: "Open Settings",
                            detail: "Return to the main Settings screen."
                        )
                        iCloudSetupStep(
                            number: 2,
                            title: "Go to iCloud Drive",
                            detail: "Your name → iCloud → Drive."
                        )
                        iCloudSetupStep(
                            number: 3,
                            title: "Turn on “Sync this iPhone”",
                            detail: "Then return to Vigil."
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if didICloudRecheckFail {
                        Label(
                            "Vigil still can’t access iCloud Drive. Check that “Sync this iPhone” is on, then try again.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(spacing: 12) {
                        Button {
                            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                                return
                            }
                            openURL(settingsURL)
                        } label: {
                            Label("Open Settings", systemImage: "gear")
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)

                        Button {
                            recheckICloudAndEnable()
                        } label: {
                            HStack {
                                if isRecheckingICloud {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isRecheckingICloud ? "Checking…" : "Check Again")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRecheckingICloud)
                    }
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not Now") {
                        cancelICloudRecheck()
                        isShowingICloudSetup = false
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var emergencyNumberEditor: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("For example, 112", text: $draftEmergencyNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .font(.title2.monospacedDigit())
                        .accessibilityLabel("Emergency number")
                } header: {
                    Text("Emergency number")
                } footer: {
                    Text("Enter the official emergency number for the country or region where you use Vigil.")
                }

                Section {
                    Label(
                        "Vigil will always show the iPhone call confirmation before placing the call.",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("SOS Number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingEmergencyNumberEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        emergencyNumber = EmergencyCallHandoff.sanitizedNumber(
                            draftEmergencyNumber
                        )
                        isShowingEmergencyNumberEditor = false
                    }
                    .disabled(
                        EmergencyCallHandoff.sanitizedNumber(draftEmergencyNumber).isEmpty
                    )
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func iCloudSetupStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.cyan, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recheckICloudAndEnable() {
        iCloudRecheckTask?.cancel()
        iCloudRecheckTask = Task {
            isRecheckingICloud = true
            didICloudRecheckFail = false

            let didEnable = await model.setSaveToICloud(true)
            guard !Task.isCancelled else { return }

            isRecheckingICloud = false
            iCloudRecheckTask = nil
            if didEnable {
                isShowingICloudSetup = false
            } else {
                didICloudRecheckFail = true
            }
        }
    }

    private func cancelICloudRecheck() {
        iCloudRecheckTask?.cancel()
        iCloudRecheckTask = nil
        isRecheckingICloud = false
    }

    private func destinationIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.title3.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
    }

    private func externalLinkRow(title: String, icon: String, urlString: String) -> some View {
        Button {
            guard let url = URL(string: urlString) else { return }
            openURL(url)
        } label: {
            HStack(spacing: 14) {
                destinationIcon(icon, color: .gray)
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
        return "\(version) (\(build))"
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

}
