import SwiftUI

@main
struct LanRDPApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 580, height: 460)
        }
    }
}
