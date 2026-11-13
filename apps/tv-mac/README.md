# tv-mac · 家里的田字格（Mac 呈现端）

Mac 上的**作业展示端**：打开就是今天的作业，和 Android TV 端同一套界面逻辑，适合接一块显示器放在书桌上当「家里的那块屏」。

- **三态**：没传（empty）/ 老师照片还没识别完（pending，4 秒一刷）/ 识别完出清单（ready，左图右清单）
- **本周日期条**：周一到周日 7 天，有作业的日子挂一朵小红花；点某天看那天，‹ › 整周翻页（最多回看 56 天）
- **看原图**：点任意照片进全屏纯黑阅读模式，上下滚动，Esc 或 × 退出
- **缓存兜底**：先渲染上次的数据再后台刷新；连不上不清屏，顶栏挂「缓存 / 上次更新 HH:mm」角标
- **自动刷新**：pending 时 4 秒一刷，其余 5 分钟一刷；App 回到前台顺手刷一次（30 秒内不重复）
- **中英双语**：跟随系统语言，中文界面「家里的田字格 TV」，英文 "Tianzige TV"
- 只读不写：上传、重跑、删除走别的端（上传 Mac 端 / Web 调试页），这里连改数据的机会都没有

## 构建

需要 macOS 13+、Xcode 15+（Swift 5.9）、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
cd apps/tv-mac
brew install xcodegen && xcodegen && open TianzigeTV.xcodeproj
```

然后在 Xcode 里：

1. 选中 target **Tianzige TV** → Signing & Capabilities，Team 选自己的 Apple ID，或保持 "Sign to Run Locally"
2. ⌘R 运行

命令行构建：

```bash
xcodebuild -project TianzigeTV.xcodeproj -scheme TianzigeTV -configuration Release build
```

产物在 `~/Library/Developer/Xcode/DerivedData/…/Build/Products/Release/TianzigeTV.app`，拷到 `/Applications` 即可。

`TianzigeTV.xcodeproj` 是 `xcodegen` 生成的，不要手改、也不要提交（见 `.gitignore`）；工程配置只改 `project.yml`。

## 用法

1. 首次打开（或连不上时）会弹设置面板，填家里 NAS 的地址，比如 `http://nas.local:8080` 或 `http://192.168.1.8:8080`
2. 点「测试连接」确认通，再点「保存」
3. 之后打开就绪：今天的作业自动出现；识别没完成时显示原图网格，识别完自动换成科目清单
4. 菜单栏「设置…」（⌘,）或右上角齿轮随时改地址

> 想当纯电视用：把窗口点成 macOS 全屏（绿色按钮 / ⌃⌘F），接一块显示器，行为就和 Android TV 端基本一致。

## 与 Android TV 端的差异

| | Android TV | Mac |
|---|---|---|
| 导航 | 遥控器焦点 | 鼠标点击 + Esc |
| 设置 | 屏幕数字键盘 | 普通文本框 |
| 退出确认 | 有 | 无（⌘Q 就是系统行为） |
| 色彩 | 固定深色 | 固定深色（扮演「那块屏」，不跟随浅色模式） |

接口协议见 [spec/openapi.yaml](../../spec/openapi.yaml)，界面规范见 [docs/04-电视端UI.md](../../docs/04-电视端UI.md)。
