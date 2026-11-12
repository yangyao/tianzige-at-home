import SwiftUI

@main
struct TianzigeApp: App {
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG
                // Reuse the installed simulator runtime for narrow native layout previews.
                .frame(width: ProcessInfo.processInfo.environment["TIANZIGE_LAYOUT_WIDTH"].flatMap(Double.init).map { CGFloat($0) })
                .frame(maxWidth: .infinity)
                #endif
                .environmentObject(settings)
                .tint(Theme.accent)
        }
    }
}
