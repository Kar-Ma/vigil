import SwiftUI

struct ContentView: View {
    @StateObject private var model = VigilModel()

    var body: some View {
        TabView {
            CaptureView(model: model, camera: model.camera)
                .tabItem {
                    Label("Record", systemImage: "record.circle")
                }

            VaultView(model: model)
                .tabItem {
                    Label("Vault", systemImage: "lock.shield")
                }
                .badge(model.recordings.count)

            SettingsView(model: model)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(.red)
        .preferredColorScheme(.dark)
        .task {
            await model.start()
        }
    }
}

#Preview {
    ContentView()
}
