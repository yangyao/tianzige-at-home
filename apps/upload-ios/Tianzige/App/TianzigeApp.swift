import SwiftUI

@main
struct TianzigeApp: App {
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .tint(Theme.accent)
        }
    }
}
