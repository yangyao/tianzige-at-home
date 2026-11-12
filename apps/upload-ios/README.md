# upload-ios · 手机上传

SwiftUI 原生 App，iOS 16+。**只做一件事：把作业照片传上去，然后走人。**
不做查看、不做浏览、不做最近上传列表——那是电视端和 Web 端的事。

## 构建

本机没有 checked-in 的 `.xcodeproj`（手写 pbxproj 容易错），用 XcodeGen 生成：

```bash
brew install xcodegen
cd apps/upload-ios
xcodegen
open Tianzige.xcodeproj
```

在 Xcode 里：

1. 选中 Tianzige target → Signing & Capabilities → Team 选你自己的
   **个人免费 Apple ID 即可**（Xcode → Settings → Accounts → 添加 Apple ID）。
   免费 ID 侧载有效期 7 天，到期重新 Run 一次就好。
2. iPhone 用数据线连上，选为自己的运行设备，⌘R。

首次安装后要在 设置 → 通用 → VPN与设备管理 里信任你的开发者证书。

## 改 NAS 地址

App 内点右上角 ⚙️ → 「NAS 地址」填家里 NAS 的局域网地址（如
`http://192.168.1.20:8080`）→ 点「测试连接」，看到绿色
「已连接 · 服务端版本 x」即生效。地址存 UserDefaults，**不填协议头会自动补 `http://`**。

## 目录结构

```
Tianzige/
├── App/            入口 + Info.plist
├── Models/         IngestResponse / HealthResponse / AppSettings / DateString
├── Networking/     APIClient（ingest + health）/ MultipartBody / ImageCompressor
└── Views/          RootView（单屏）/ SettingsView / 选图器 / Theme
```

## 行为约定（与 docs/05-协议.md、design/upload-ui.md 对齐）

- 只调两个接口：`POST /api/ingest` 和 `GET /api/health`。
- **提交即走**：收到 202 立即清空表单 + toast「收到 N 张，处理完电视上就有」，
  绝不轮询识别结果。
- 失败 / 30s 超时：按钮变红「没传上去，点这里重试」，已选图片保留，一键重发。
- `duplicate_of` 有值：toast「这些图片之前传过了，没有重复入库」。
- 剪贴板：进前台时只做 `hasImages` 存在性判断（不弹系统提示），
  用户点「添加」才真正读（此时系统会弹一次粘贴提示）。
- 图片压缩：最长边 2048px、JPEG 0.85，HEIC 统一转 JPEG（服务端不收 heic 更稳）。
- 日期一律按 **Asia/Shanghai** 格式化成 `YYYY-MM-DD`，默认今天，
  可往前补传 7 天（协议 §6）。
- 服务不通：顶部黄条「连不上 NAS，检查地址或网络」，点黄条直达设置页。
- 深色模式跟随系统；色值/字号全部来自 `design/tokens.json`
  （见 `Views/Theme.swift`，注释里标了 token 名）。

## 权限说明（Info.plist）

| 键 | 用途 |
|---|---|
| `NSPhotoLibraryUsageDescription` | 相册选图（实际走 PHPicker，只读选中的那张） |
| `NSCameraUsageDescription` | 直接拍照 |
| `NSLocalNetworkUsageDescription` | 连接局域网 NAS，iOS 14+ 会弹本地网络授权 |
| `NSAppTransportSecurity` | NAS 是局域网 `http://`，需要放行明文（`NSAllowsLocalNetworking` + `NSAllowsArbitraryLoads`，仅限自用，不出公网） |

## 已知取舍

- 没接 AppIcon 之外的动态资源；图标是从 `design/app-icon.svg` 手工栅格化的。
- 上传用内存里的 JPEG Data（≤6 张 × ~1MB），不做断点续传——局域网内没必要。
- 不做 Widget / Shortcuts / 推送（upload-ui.md §6 明确不做）。
- 2026-11-12：已在本机 Xcode 27.2 完成 Debug / Release 设备构建与已有 iOS 27.1 模拟器启动。iPhone 真机签名安装尚未验证。

统一构建入口：在仓库根目录运行 `sh scripts/build-apple.sh`，不会下载 SDK 或模拟器。产物 `dist/Tianzige-iOS-unsigned.zip` 未签名，真机安装需在 Xcode 选择 Team。

默认 NAS 地址为 `http://192.168.2.196:18086`，无需首次填写。旧默认 `nas.local:8080` 自动迁移，用户自定义地址保留。当前采用预设地址；NAS IP 改变时需修改设置，尚未实现服务发现。

`sh scripts/package-ios.sh`（项目根目录执行）生成标准 Payload 结构的 IPA，可复制到 LiveContainer 后导入。
