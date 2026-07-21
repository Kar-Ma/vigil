import SwiftUI

struct ContentView: View {
    @StateObject private var model = VigilModel()
    @StateObject private var vaultAccess = VaultAccessController()
    @StateObject private var screenCurtain = ScreenCurtainController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingSettings = false

    var body: some View {
        CaptureView(
            model: model,
            camera: model.camera,
            screenCurtain: screenCurtain,
            allowsScreenCurtainGesture: !isShowingSettings
        ) {
            screenCurtain.deactivateWhenLeavingForeground()
            isShowingSettings = true
        }
        .tint(.red)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingSettings, onDismiss: vaultAccess.lock) {
            SettingsView(
                model: model,
                vaultAccess: vaultAccess,
                googleDrive: model.googleDrive,
                screenCurtain: screenCurtain
            )
                .preferredColorScheme(.dark)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            model.camera.appDidBecomeActive()
            handleQuickRecordingRequest()
            await model.start()
            model.camera.appDidBecomeActive()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.camera.appWillLeaveForeground()
            }
            if phase == .background {
                vaultAccess.lock()
                screenCurtain.deactivateWhenLeavingForeground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: QuickRecordingRequest.notification)) { _ in
            handleQuickRecordingRequest()
        }
    }

    private func handleQuickRecordingRequest() {
        guard scenePhase == .active, QuickRecordingRequest.consumeIfRecent() else { return }
        screenCurtain.deactivateWhenLeavingForeground()
        isShowingSettings = false
        model.requestQuickRecording()
    }
}

#Preview {
    ContentView()
}
