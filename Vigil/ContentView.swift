import SwiftUI

struct ContentView: View {
    @StateObject private var model = VigilModel()
    @StateObject private var vaultAccess = VaultAccessController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingSettings = false

    var body: some View {
        CaptureView(model: model, camera: model.camera) {
            isShowingSettings = true
        }
        .tint(.red)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingSettings, onDismiss: vaultAccess.lock) {
            SettingsView(model: model, vaultAccess: vaultAccess)
                .preferredColorScheme(.dark)
        }
        .task {
            await model.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                vaultAccess.lock()
            }
        }
    }
}

#Preview {
    ContentView()
}
