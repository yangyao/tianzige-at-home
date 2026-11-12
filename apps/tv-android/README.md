# tv-android · 电视端

Kotlin + Compose for TV 原生 App。

## 状态

**未开始。** 先用 `apps/upload-web/today.html` 在电视浏览器里验证体验。

## 计划

- minSdk 21 / targetSdk 34，`applicationId: com.homework.tv`
- 单 Activity + Compose，Leanback 不需要
- 焦点：日期条用 `LazyRow` + `focusRequester`，内容区不参与焦点
- 网络：OkHttp + kotlinx.serialization
- 图片：Coil，本地缓存原图（断网可看）
- 配置：NAS 地址写在 `BuildConfig`，首次启动可输入

## 接口

见 `docs/03-接口.md` 的 `GET /today`。

## 安装

```bash
adb connect <tv-ip>:5555
adb install -r app-debug.apk
```

国产电视需在设置里打开「允许安装未知来源应用」。
