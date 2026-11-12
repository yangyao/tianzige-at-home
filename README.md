# homework-tv · 电视上的今日作业

把老师在 QQ 群里发的黑板作业照片，变成孩子打开电视就能看到的「今日作业」。

**解决的问题**：孩子记不住作业，只能拿大人的手机打开 QQ 翻照片，而大人的手机不可能一直给他。

---

## 一条链路

```
老师拍黑板 → QQ 群
                │
                ├── 自动：Mac mini 上的 Codex（定时，Computer Use）
                └── 手动：网页上传页（截图粘贴 / 手机拍照）
                          │
                          ▼
                  NAS · Go 服务
                  ├── 落盘（原图）
                  ├── OCR（文字）
                  ├── 分科（语文 / 数学 / 英语）
                  └── SQLite
                          │
                          ▼
                  Android TV 原生 App
                  ├── 打开就是今天
                  ├── ← → 看前几天
                  ├── OK 看大图
                  └── ↑ ↓ 换科目
```

## 仓库结构

```
apps/
  tv-android/         电视端（Kotlin + Compose for TV，原生）
  upload-ios/         手机上传（SwiftUI，原生）
  upload-mac/         电脑上传（SwiftUI，拖拽 / 菜单栏，原生）
  upload-web/         网页上传（可选，先跑通用，也是接口参考实现）
services/
  homework-server/    NAS 上的服务（Go + SQLite）
design/               电视端 UI 设计稿（可直接在浏览器打开）
docs/                 需求、方案、接口、UI 规范
```

## 技术选型

| 层 | 选型 | 理由 |
|---|---|---|
| 电视端 | Kotlin + Compose for TV | 原生、遥控器焦点模型成熟 |
| 手机 / 电脑端 | SwiftUI | 原生，能直接调相机、拖拽、剪贴板 |
| 服务端 | Go + SQLite | 单二进制、无依赖，NAS 上跑得动 |
| 网页上传 | 原生 HTML/JS | 可选，用来验证接口和应急兜底 |

**移动端和桌面端一律原生**，不做跨平台壳；网页版只作为可选项存在。

## 现在到哪一步了

- [x] 需求与方案文档
- [x] 电视端 UI 设计稿（`design/tv-ui-design.html`）
- [x] 网页上传页（`apps/upload-web/upload.html`，可跑）
- [x] 电视端展示页（`apps/upload-web/today.html`，临时用浏览器验证）
- [ ] Go 服务（`services/homework-server`）
- [ ] Android TV App
- [ ] iOS / macOS 上传 App
- [ ] Mac mini 自动采集

## 快速看效果

不用装任何东西，直接用浏览器打开：

```bash
open design/tv-ui-design.html        # 电视端设计稿，底部按钮切 6 种状态
open apps/upload-web/upload.html     # 上传页，无后端时自动进演示模式
```

## 不做什么

- 不做题库、不做练习、不给答案
- 不做账号体系、不做多租户、不上公网
- 不做「家长监控孩子」的功能

这个项目只解决一件事：**让孩子自己看得到今天的作业**。
