import SwiftUI

@main
struct LanRDPApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsRootView()
                .environmentObject(store)
                .frame(width: 580, height: 460)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        ContentView()
            .environment(\.locale, Locale(identifier: store.settings.language.localeIdentifier))
    }
}

private struct SettingsRootView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        SettingsView()
            .environment(\.locale, Locale(identifier: store.settings.language.localeIdentifier))
    }
}
