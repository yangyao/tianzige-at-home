# upload-mac · 电脑上传

SwiftUI 原生 App，主要形态是**拖拽 + 菜单栏常驻**。

## 状态

**未开始。** 当前用 `apps/upload-web/upload.html` 在浏览器里替代。

## 核心场景

在 Mac 上截完图（`⌘⇧4`），图已经在剪贴板 / 桌面上 → 拖进 App 或按快捷键 → 上传。

## 计划

- 菜单栏图标常驻，点击弹出小面板
- 主区域接收拖拽，也接收 `⌘V` 粘贴
- 支持多图，可排序
- 上传后不阻塞，面板收起
- 和 iOS 共享上传逻辑（Network + Models 抽成 Swift Package）
