import SwiftUI

@main
struct WhisperBoxApp: App {
    @State private var controller = WhisperBoxController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: controller)
        } label: {
            Image(systemName: controller.menuBarIcon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(controller.menuBarColor)
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView(controller: controller)
        }
    }
}
