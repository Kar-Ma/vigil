import SwiftUI

struct ContentView: View {
    private enum Tab: Hashable {
        case record
        case vault
        case settings
    }

    @StateObject private var model = VigilModel()
    @StateObject private var vaultAccess = VaultAccessController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .record

    var body: some View {
        TabView(selection: $selectedTab) {
            CaptureView(model: model, camera: model.camera)
                .tag(Tab.record)
                .tabItem {
                    Label("Record", systemImage: "record.circle")
                }

            VaultView(model: model, access: vaultAccess)
                .tag(Tab.vault)
                .tabItem {
                    Label("Vault", systemImage: "lock.shield")
                }
                .badge(model.recordings.count)

            SettingsView(model: model)
                .tag(Tab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(.red)
        .preferredColorScheme(.dark)
        .task {
            await model.start()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .vault {
                vaultAccess.unlock()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                vaultAccess.lock()
            case .active where selectedTab == .vault:
                vaultAccess.unlock()
            default:
                break
            }
        }
    }
}

#Preview {
    ContentView()
}
