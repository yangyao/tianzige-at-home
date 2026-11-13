import AppKit
import SwiftUI

/// 自建 NSWindow 而不是 SwiftUI `Window` scene。
///
/// 原因：MenuBarExtra-only 的 App 如果再加 `Window` scene，启动时 SwiftUI 会自动把那个窗口弹出来；
/// 自建窗口能精确控制「启动时只有菜单栏图标、点菜单才出现窗口」，也能控制 460×520 的固定尺寸。
///
/// 关于 Dock 图标：Info.plist 里 LSUIElement=true，平时不占 Dock；
/// 窗口打开时临时切成 .regular，让 Dock 图标出现（这样把图片拖到 Dock 图标上才有落点），
/// 最后一个窗口关掉后再切回 .accessory。
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var uploadWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private weak var store: UploadStore?
    private lazy var pasteMonitor = PasteMonitor()

    func configure(store: UploadStore) {
        self.store = store
    }

    // MARK: - 窗口

    func showUploadWindow() {
        let store = resolvedStore()
        if uploadWindow == nil {
            let root = UploadWindow()
                .environmentObject(store)
            uploadWindow = makeWindow(
                title: L10n.string("window.upload.title"),
                size: NSSize(width: 560, height: 700),
                rootView: AnyView(root)
            )
        }
        present(uploadWindow)
        // 只有上传窗口是 key window 时才拦 ⌘V
        pasteMonitor.start(
            isActive: { [weak self] in self?.uploadWindow?.isKeyWindow == true },
            handler: { store.pasteFromClipboard() }
        )
    }

    func showSettingsWindow() {
        let store = resolvedStore()
        if settingsWindow == nil {
            let root = SettingsView()
                .environmentObject(store)
            settingsWindow = makeWindow(
                title: L10n.string("settings.title"),
                size: NSSize(width: 400, height: 250),
                rootView: AnyView(root)
            )
        }
        present(settingsWindow)
    }

    func closeSettingsWindow() {
        settingsWindow?.performClose(nil)
    }

    /// AppDelegate 一般会提前 configure；这里再兜一层，保证拖文件启动时也有 store。
    private func resolvedStore() -> UploadStore {
        if let existing = store { return existing }
        let store = UploadStore.shared
        self.store = store
        return store
    }

    private func makeWindow(title: String, size: NSSize, rootView: AnyView) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(size)
        // 固定尺寸：最小 = 最大，拖不动边框，也不会被布局撑大。
        window.contentMinSize = size
        window.contentMaxSize = size
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()                 // macOS 14 起的新 API
        } else {
            NSApp.activate(ignoringOtherApps: true)  // macOS 13 只有这个
        }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        // 每次回到上传窗口都顺手看一眼 NAS 在不在，黄条不至于一直挂着旧状态。
        guard let window = notification.object as? NSWindow, window === uploadWindow,
              let store = store else { return }
        if case .ok = store.health { return }
        store.refreshHealth(force: true)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === uploadWindow {
            pasteMonitor.stop()
        }
        // 关闭动画期间窗口还是 visible，等这一轮 runloop 结束再判断；正在关闭的这个不算。
        let closing = notification.object as? NSWindow
        Task { @MainActor in
            let anyVisible = NSApp.windows.contains {
                $0.isVisible && $0.canBecomeMain && $0 !== closing
            }
            if !anyVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
