import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    /// 菜单栏「设置…」（⌘,）→ 让 VM 弹出设置面板。
    static let tzOpenSettings = Notification.Name("tzOpenSettings")
}

@main
struct TianzigeTVApp: App {
    var body: some Scene {
        WindowGroup(L10n.string("window.title")) {
            ContentView()
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.string("menu.settings")) {
                    NotificationCenter.default.post(name: .tzOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = HomeViewModel()

    /// pending 时 4 秒一刷（等识别结果），其余靠节律控制在 VM 里。
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    private var settingsBinding: Binding<Bool> {
        Binding(
            get: { vm.state.showSettings },
            set: { if !$0 { vm.closeSettings() } }
        )
    }

    var body: some View {
        GeometryReader { geo in
            HomeView(vm: vm)
                .environment(\.tz, .fit(height: geo.size.height))
        }
        .background(Tz.bgBase)
        .sheet(isPresented: settingsBinding) {
            SettingsSheet(vm: vm)
        }
        .overlay {
            if vm.state.fullscreen {
                FullscreenViewer(url: vm.state.fullscreenUrl) {
                    vm.closeFullscreen()
                }
                .transition(.opacity)
            }
        }
        .onReceive(timer) { _ in
            vm.refreshIfNeeded(backgroundPoll: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.refreshIfBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tzOpenSettings)) { _ in
            vm.openSettings()
        }
    }
}
