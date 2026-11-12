# upload-mac · 家里的田字格

Mac 上的**菜单栏快速投递入口**：把老师发在 QQ 群里的作业截图拖进来 / 按 ⌘V，传到家里 NAS，然后就没你的事了。

- 形态：`MenuBarExtra` 常驻菜单栏，菜单栏图标是一个「田」字
- 只做上传：没有作业查看界面、没有最近列表、没有重跑 / 删除（那些是电视端和 Web 调试页的事）
- 不做文件夹监听、定时抓取（QQ 群自动抓取在 Mac mini 上由 Codex 走 `POST /api/ingest`，是另一条路）

状态：源码完成，**本仓库的写作环境是 Linux、没有 Swift 工具链**，尚未在 Xcode 里编译过。
第一次在 Mac 上打开如果报错，优先看 [已知风险](#已知风险没编译验证过) 一节。

## 构建

需要 macOS 13+、Xcode 15+（Swift 5.9）、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
cd apps/upload-mac
brew install xcodegen && xcodegen && open TianzigeMac.xcodeproj
```

然后在 Xcode 里：

1. 选中 target **Tianzige Mac** → Signing & Capabilities
2. Team 选自己的 Apple ID（Personal Team），或保持 "Sign to Run Locally"（不需要开发者账号）
3. ⌘R 运行。Dock 里不会出现 App，菜单栏多一个「田」字图标

命令行构建：

```bash
xcodebuild -project TianzigeMac.xcodeproj -scheme TianzigeMac -configuration Release build
```

产物在 `~/Library/Developer/Xcode/DerivedData/…/Build/Products/Release/TianzigeMac.app`，拷到 `/Applications` 即可。

`TianzigeMac.xcodeproj` 是 `xcodegen` 生成的，不要手改、也不要提交（见 `.gitignore`）；工程配置只改 `project.yml`。

## 用法

菜单栏图标点开：

- **打开上传窗口…**
- **上次：✓ 3 张 · 17:32**（只读，AppStorage 记录，跨启动保留）
- **设置…**
- **退出**

上传窗口 460 × 520：

| 动作 | 结果 |
|---|---|
| 图片拖到窗口任意位置 | 进「已选图片」，最多 6 张 |
| ⌘V | 剪贴板里的截图 / 复制的图片文件进列表 |
| 点虚线框 | 打开系统选图面板 |
| 拖到 Dock 图标 | 图片进列表（窗口开着时 Dock 才有图标，见下） |
| 缩略图右上角 × | 拿掉这一张 |

填写「老师的话」（可选，500 字上限）、日期（默认今天，可改成前几天补传），点「上传（N 张）」。
拿到 202 立刻清空表单，窗口内 toast「收到 N 张，处理完电视上就有」，6 秒后消失。
所有图片之前传过时 toast 改成「这些图片之前传过了，没有重复入库」。
失败（4xx / 5xx / 30 秒超时 / 连不上）按钮变红「没传上去，点这里重试」，图片全部保留，再点一次就重发。
窗口顶部黄条「连不上 NAS，检查地址或网络」只在健康检查明确失败后出现。

设置窗口只有两项：NAS 地址（默认 `http://nas.local:8080`，`@AppStorage` 存 UserDefaults）+「测试连接」（`GET /api/health`）。
地址允许只填 `192.168.1.8:8080`，会自动补 `http://`。

## 签名与首次打开（自用侧载）

自用不需要公证、不需要 App Store。

- **免费签名**：Xcode 里选 Personal Team 即可（免费 Apple ID）。免费账号签出来的 App 过一段时间证书会失效（iOS 上通常是 7 天），失效后重新 build 一次就行。
  只在本机用的话，选 "Sign to Run Locally"（ad-hoc 签名）更省事，没有过期问题，但不能拷给别人。
- **Gatekeeper**：从 Finder 双击首次打开会提示「无法验证开发者」。两种办法：
  1. 右键 App → 打开 → 再点「打开」
  2. 系统设置 → 隐私与安全性 → 拉到底 → 「仍要打开」
- 如果 App 是从别处下载 / 通过网盘拷来的，还可以去掉隔离标记：
  ```bash
  xattr -dr com.apple.quarantine /Applications/TianzigeMac.app
  ```
- **公证**只在要分发给别人时才需要：Developer ID 证书 + 打开 Hardened Runtime + `xcrun notarytool submit` + `xcrun stapler staple`。家里自用没必要。

## 实现说明

### 为什么窗口是自建 NSWindow

App 唯一的 SwiftUI scene 是 `MenuBarExtra`。如果再加一个 `Window` scene，启动时 SwiftUI 会自动弹出那个窗口（MenuBarExtra-only App 的已知行为），而我们要的是「启动后只有菜单栏图标」。
所以上传 / 设置窗口由 `WindowManager`（`NSWindow` + `NSHostingController`）自己管，窗口内容仍然是 SwiftUI（`UploadWindow` / `SettingsView`），固定 460×520 / 400×250，不可缩放。

### 菜单栏图标与 Dock

- `Info.plist` 里 `LSUIElement = true`，平时没有 Dock 图标，也不出现在 ⌘Tab。
- 打开窗口时临时 `NSApp.setActivationPolicy(.regular)`，让 Dock 出现图标——这样「把图片拖到 Dock 图标上」才有落点，`CFBundleDocumentTypes` 也才用得上。最后一个窗口关闭后切回 `.accessory`。
- 图标本身是 `Canvas` 画的方形 + 横竖中线（`MenuBarIcon`），文字色 `Color.primary` 跟随菜单栏深浅色。

### 图片预处理

用 ImageIO（`CGImageSource`）而不是 `NSImage` 缩放：

- 最长边 ≤ 2048（只缩不放），`kCGImageSourceCreateThumbnailWithTransform` 按 EXIF 方向转正
- 透明底铺白再编码，避免截图 alpha 在 JPEG 里变黑块
- 统一转 JPEG 0.85，所以服务端收到的永远 `image/jpeg`；20MB 上限只是兜底
- 列表缩略图另存 320px 的小 `NSImage`，6 张大图不会全部驻留内存
- 解码 / 编码在 `Task.detached` 后台做，窗口不卡

### 网络

- 只调 `POST /api/ingest` 和 `GET /api/health`，不调批次列表，不轮询
- `timeoutIntervalForRequest = 30`（上传），健康检查 6s
- `waitsForConnectivity = false`：地址写错时立刻失败变红，而不是让按钮转 30 秒
- `URLSessionConfiguration.ephemeral`：不落缓存
- 拿到 202 只解析 `batch_id / image_count / duplicate_of`，然后清空表单
- 失败文案：优先用服务端返回的 `error.message`（协议规定它是可直接展示的中文）；网络错误用「连不上 NAS」

### 剪贴板 ⌘V 为什么用 NSEvent

窗口是自建 `NSWindow`，`.onPasteCommand` 依赖 responder chain 里有对象处理 `paste:`；焦点落在窗口空白处时它不一定被调用。
`PasteMonitor` 用 `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` 在事件进入 responder chain 之前拦截 ⌘V：

- 剪贴板里有图片 → 消费事件、加图
- 焦点在备注框里、且剪贴板同时有文字 → 放行，让系统正常贴文字

`AppDelegate` 里另外补了一个最小主菜单（App + 编辑），备注框里的 ⌘C / ⌘V / ⌘A 才能正常工作。

### 其他取舍

- **不开沙盒**（没有 entitlements）：需要读用户从任意路径拖进来的文件，自用工具，沙盒只会增加摩擦
- **ATS 全放开**：地址由用户填，可能是 `http://192.168.x.x`，明文 HTTP 必须放开，否则请求被系统直接拦掉
- **深浅色**：`Theme.swift` 里 `tokens.json` 的深色值原样使用；浅色取同对比关系的对应值（tokens 只给了深色一套），注释标了 token 名
- **日期**：DatePicker 用 `Asia/Shanghai` 时区显示，提交前格式化成 `YYYY-MM-DD`，不发送时间戳

## 目录

```
apps/upload-mac/
├── project.yml                 XcodeGen 工程定义（唯一工程真源）
├── Info.plist                  LSUIElement、文档类型、ATS、局域网用途说明
├── README.md
├── ProtocolTests.md            接口请求 / 响应示例与客户端行为对照
└── Sources/
    ├── TianzigeMacApp.swift    @main、MenuBarExtra、菜单项、AppDelegate（Dock drop / reopen）
    ├── Core/
    │   ├── Theme.swift         tokens.json → 颜色 / 字号 / 间距 / 圆角
    │   ├── Models.swift        IngestResponse / HealthResponse / 错误体 / IngestError
    │   ├── APIClient.swift     multipart 构造、30s 超时、地址归一化
    │   ├── ImageProcessor.swift 2048px / JPEG 0.85 / 白底 / 缩略图
    │   ├── ClipboardReader.swift 剪贴板里的图片文件和 NSImage
    │   ├── PasteMonitor.swift  ⌘V 本地事件监控
    │   ├── UploadStore.swift   全部窗口状态 + 上传流程 + 上次上传记录
    │   └── WindowManager.swift 自建窗口、激活策略切换
    └── UI/
        ├── UploadWindow.swift  上传窗口
        ├── SettingsView.swift  设置窗口
        ├── DropSupport.swift   全窗 DropDelegate
        └── Glyphs.swift        菜单栏「田」字 + 2×2 格子
```

## 已知风险（没编译验证过）

写作环境没有 macOS / Swift，下面是人工审查后仍可能第一次编译踩到的点：

1. **SwiftUI 并发标注**：`UploadStore` 是 `@MainActor`，DropDelegate 里用 `Task { @MainActor in }` 跳回主线程；NSEvent 回调依赖「非 Sendable 闭包继承外层 actor」这条规则。如果 Xcode 的并发检查更严格，可能要给 `PasteMonitor.start` 的 handler 调用再包一层 `Task { @MainActor in }`。
2. **MenuBarExtra + Canvas**：菜单栏自定义视图一般会用 `.primary` 自动反色；若在浅色菜单栏下颜色不对，改成 `NSImage(size:flipped:drawingHandler:)` 画好并设 `isTemplate = true` 即可（注释里留了思路）。
3. **Dock 拖放**：依赖「窗口打开时切 `.regular`」，窗口关闭时 Dock 图标消失。这是为满足 `LSUIElement=true` + 「Dock 图标接受文件」两个要求做的折中。
4. **`NSItemProvider.loadItem` 的返回类型**：Finder 拖拽可能给 `Data` 或 `NSURL`，代码两种都处理了；极端情况下某些 App 提供 file promise，会走 `loadDataRepresentation` 分支。
5. **ATS**：`NSAllowsArbitraryLoads = true` 是给自用工具开的口子；如果要上架需要改成 `NSExceptionDomains`。
6. **App 图标**：没有放 `Assets.xcassets`，用系统默认图标。菜单栏图标不受影响。
7. **用 Xcode 16 / macOS 15+ SDK 编译**：AppKit 的 `@MainActor` 标注比 Xcode 15 更严，`Theme.swift` 里用 `NSColor` 动态色的静态属性可能需要整体标 `@MainActor`（或改成 `Color(red:green:blue:)` 字面量）。按本文的 Xcode 15 环境不受影响。

## 协议

字段级定义以 [`spec/openapi.yaml`](../../spec/openapi.yaml) 为唯一真源；本端只依赖两个接口。
请求 / 响应示例、multipart 原文、错误与重试行为对照见 [ProtocolTests.md](ProtocolTests.md)。
