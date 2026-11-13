import AppKit
import SwiftUI

@main
struct TianzigeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.menu)
    }
}

/// 菜单栏菜单：打开上传窗口 / 上次上传状态 / 设置 / 退出
struct MenuContent: View {
    // 上次上传状态用 @AppStorage 存，跟着 App 重启也还在
    @AppStorage(DefaultsKey.lastUploadCount) private var lastCount = 0
    @AppStorage(DefaultsKey.lastUploadAt) private var lastAt = 0.0
    @AppStorage(DefaultsKey.lastUploadDuplicate) private var lastDuplicate = false

    var body: some View {
        Button(L10n.string("menu.openWindow")) {
            WindowManager.shared.showUploadWindow()
        }

        Text(lastUploadText)

        Divider()

        Button(L10n.string("menu.settings")) {
            WindowManager.shared.showSettingsWindow()
        }

        Divider()

        Button(L10n.string("menu.quit")) {
            NSApp.terminate(nil)
        }
    }

    private var lastUploadText: String {
        guard lastCount > 0, lastAt > 0 else { return L10n.string("menu.last.none") }
        let time = Self.clockFormatter.string(from: Date(timeIntervalSince1970: lastAt))
        if lastDuplicate {
            return L10n.format("menu.last.duplicate", time)
        }
        if lastCount == 1 {
            return L10n.format("menu.last.count.one", time)
        }
        return L10n.format("menu.last.count", lastCount, time)
    }

    /// 24 小时制，两边一致（docs/12-国际化.md §5）。
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement=true 已经让我们没有 Dock 图标，这里再显式收一下，避免窗口管理把策略改乱。
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.makeMainMenu()
        WindowManager.shared.configure(store: UploadStore.shared)
        if CommandLine.arguments.contains("--upload") {
            WindowManager.shared.showUploadWindow()
        }
    }

    /// 最小主菜单：App 菜单 + 编辑菜单。
    /// 自建窗口没有 SwiftUI 的菜单，备注框里的 ⌘C / ⌘V / ⌘A 要靠编辑菜单里的标准 action 才能走通。
    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: L10n.string("menu.about"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: L10n.string("menu.hide"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: L10n.string("menu.quitApp"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: L10n.string("menu.edit"))
        editMenu.addItem(withTitle: L10n.string("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.string("menu.redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.string("menu.cut"), action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.string("menu.copy"), action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.string("menu.paste"), action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.string("menu.selectAll"), action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu

        return mainMenu
    }

    /// Finder / Dock 图标拖文件、右键「打开方式」都会走这里（等价于 SwiftUI 的 .onOpenURL）。
    func application(_ application: NSApplication, open urls: [URL]) {
        let images = urls.filter { ImageProcessor.isSupportedImage($0) }
        guard !images.isEmpty else { return }
        WindowManager.shared.showUploadWindow()
        UploadStore.shared.add(sources: images.map { ImageSource(fileURL: $0) })
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowManager.shared.showUploadWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
