# tv-android · 电视端

Kotlin + Compose for TV 原生 App。单 Activity、全 Compose、不用 Leanback 老体系。

孩子用遥控器（← → ↑ ↓ / OK / 返回）看「今日作业」：本周日期条选日期，左图右文看科目，
OK 进全屏看原图。识别没完成也能先看图，断网时显示上一次缓存的数据。

## 功能

- 首屏 = 今天的作业；← → 换日期（跨周自动翻），日期条圆点 = 这天有作业（`/api/days`）
- ↑ ↓ 换科目（`ready`）或换图（`pending`），OK 全屏看原图，↑↓ 滚动，返回退出
- 三态严格分开：`empty`「今天还没有作业」/ `pending`「正在识别，先看图 · 图是准的」/ `ready` 左图右文
- 容错：先渲染本地缓存再后台刷新；网络失败保留旧数据 + 标题角标「上次更新 HH:mm」；
  完全没有缓存才显示错误页；5 秒超时
- 设置屏：按遥控器**菜单键**进入，IP 数字键盘输入服务端地址（默认 `http://nas.local:8080`），
  支持「保存 / 测试连接 / 清除」，地址存在 SharedPreferences
- 首次启动连不上服务端会自动进入设置屏

字段与接口以 [`spec/openapi.yaml`](../../spec/openapi.yaml) 为唯一真源，只调
`GET /api/day`、`GET /api/days`、`GET /api/health`。

## 环境要求

- Android Studio（Hedgehog 及以上，自带 JDK 17 即可）或命令行 Gradle 8.7+
- Android SDK：Platform 34 + Build-Tools 34（Android Studio 会自动装）

## 构建

1. 用 Android Studio `File → Open` 打开 `apps/tv-android` 这个目录（不是仓库根目录）。
2. 首次打开如果提示找不到 SDK，确认/新建 `local.properties`（在 `.gitignore` 里，不会入库）：

   ```properties
   sdk.dir=/path/to/Android/Sdk
   ```

   一般 Android Studio 会自动生成这一步，改一下路径即可。
3. Sync 之后 `Run` 或命令行：

   ```bash
   ./gradlew :app:assembleDebug
   # 产物：app/build/outputs/apk/debug/app-debug.apk
   ```

4. 单元测试（纯 JVM，不需要设备）：

   ```bash
   ./gradlew :app:testDebugUnitTest
   ```

> 依赖版本全部写死（Compose BOM 2024.06.00 / tv-material 1.0.0 / Kotlin 1.9.24），
> 不用动态版本；首次构建需要联网下载依赖。

## 安装到电视 / 盒子

```bash
adb connect <电视IP>:5555     # 部分盒子端口是 5037 或需要在设置里打开「网络调试/ADB」
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### 国产电视开「未知来源」

- **小米**：设置 → 账号与安全 → 安全 → 允许安装未知来源应用；另需在「设置 → 设备偏好 → 关于」连按「产品型号」打开开发者模式，再在「开发者选项」里开「USB 调试 / 网络 ADB」。
- **华为/荣耀**：设置 → 系统 → 关于设备，连按「产品型号」进开发者模式；设置 → 安全 → 更多安全设置 → 允许安装未知来源应用。
- **海信**：设置 → 通用 → 安全 → 未知来源；部分机型需要在「关于」连按确认键打开工厂菜单里的 ADB。
- **TCL/雷鸟**：设置 → 设备偏好设置 → 安全和限制 → 未知来源；安装时用「安装包管理器」确认。

各家系统版本差异很大，找不到就在设置里搜「未知来源」或「ADB」。

## 服务端地址怎么改

- 默认 `http://nas.local:8080`。`nas.local` 依赖 mDNS，很多电视盒子解析不了，
  **建议直接填 NAS 的局域网 IP**，例如 `192.168.1.8:8080`（协议会自动补 `http://`）。
- 电视上按遥控器**菜单键**进设置屏，用数字键盘输入（方向键移动、OK 输入、⌫ 退格），
  「测试连接」会调 `/api/health`，显示服务版本即表示通了，然后「保存」。
- 图片 URL 服务端只给相对路径（`/img/...`），客户端拼 base，换端口/换 IP 不影响数据。

## 键位

| 键 | 主屏 | 全屏看图 | 设置屏 |
|---|---|---|---|
| ← → | 换日期（跨周自动翻） | — | 移动 |
| ↑ ↓ | 换科目 / 换图 | 滚动图片 | 移动 |
| OK | 看大图 | — | 输入 / 确认 |
| 返回 | 退出确认 | 关闭 | 回主屏 |
| 菜单 | 进设置 | — | 回主屏 |

## 工程结构

```
app/src/main/java/com/tianzige/tv/
├── MainActivity.kt          # 单 Activity
├── data/                    # Models(kotlinx.serialization)、TvApi(OkHttp)、CacheStore、SettingsStore
├── domain/                  # 纯函数：DayLogic（日期/标题/三态/URL 拼接）、SettingsPad、ErrorText
├── ui/
│   ├── theme/Theme.kt       # tokens.json 的色值/字号（含 1080p 设计稿到任意分辨率的换算）
│   ├── TvRoot.kt            # 按键路由：全局唯一焦点，方向键在这里被消费
│   ├── HomeScreen.kt        # 标题区 + 日期条 + 内容 + 键位提示
│   ├── DateStrip.kt         # 本周 7 天 + 圆点
│   ├── DayPanels.kt         # pending / ready（左图右文）
│   ├── FullscreenViewer.kt  # 全屏看图
│   ├── SettingsScreen.kt    # IP 数字键盘设置屏
│   └── ExitConfirm.kt
└── vm/HomeViewModel.kt      # 唯一状态持有者：缓存优先、失败保旧、自动刷新
```

- 缓存：最近一次成功的 `/api/day`、`/api/days` 存在 app 私有目录 `files/cache/*.json`，
  启动先渲染再后台刷新。
- 焦点：只有日期条上那一个真实焦点；方向键全部在根节点被拦截分发，
  所以「焦点在哪儿」永远只有一个答案，也没有惯性滚动。
- 色值/字号全部来自 [`design/tokens.json`](../../design/tokens.json)（见 `ui/theme/Theme.kt` 的注释）。
