import AppKit

/// 窗口内的 ⌘V 监听。
///
/// 为什么用 NSEvent 本地监控而不是 `.onPasteCommand`：
/// - 窗口是自建的 NSWindow，`.onPasteCommand` 依赖 responder chain 里有人处理 `paste:`，
///   焦点落在窗口空白处时它不一定被调用；
/// - AppKit 的 keyDown 本地监控在事件进入 responder chain 之前就能拿到，行为确定。
///
/// 不抢输入框：当焦点在文本编辑器里、且剪贴板同时有文字时，放行给系统贴文字。
@MainActor
final class PasteMonitor {
    private var monitor: Any?

    /// isActive / handler 都在主线程执行。
    /// isActive 用来保证只有上传窗口是当前窗口时才拦截 ⌘V，别的窗口不抢。
    func start(
        isActive: @escaping @MainActor () -> Bool,
        handler: @escaping @MainActor () -> Void
    ) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "v",
                  isActive()
            else { return event }

            let editingText = NSApp.keyWindow?.firstResponder is NSTextView
            if editingText && ClipboardReader.hasText() {
                return event
            }
            guard ClipboardReader.hasImage() else { return event }

            // 事件已经被我们消费。回调本身在主线程，直接执行即可。
            handler()
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
