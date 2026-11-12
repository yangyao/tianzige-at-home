# 电视端

Kotlin + Compose Material3 原生 App，单 Activity，不使用 WebView。
首屏打开今天；各科作业同时展开，日期与照片使用原生空间焦点导航。
不显示同步状态、同步时间和遥控器说明，没有科目 Tab。
照片上确认打开大图，返回关闭；菜单键进入 NAS 地址设置。

## 构建

在仓库根目录运行 sh scripts/build-tv.sh。
复用已有 Gradle 8.9、AGP 8.5.2、Kotlin 2.0.20、Compose BOM 2024.02.02、JDK 17、Android 34。
脚本 --offline，不下载安装组件，输出 dist/tianzige-tv-debug.apk。
同时执行 33 个 JVM 测试和 lint。最低 Android API 26。

本轮按用户要求只在已有 tv34 模拟器做运行验收。
安装必须显式指定设备，例如 adb -s emulator-5554 install -r dist/tianzige-tv-debug.apk，
避免连接了真机时误装。本轮曾在用户改为模拟器之前完成一次真机安装，后续未启动或配置真机应用。

## 数据

只读取 /api/day、/api/days、/api/health。默认服务地址为 http://nas.local:8080，
实际部署通过设置填写 NAS 的局域网 IP 与端口，地址不硬编码进源码。
原图完整显示，识别未准备好也能先看图。
缓存使用 SharedPreferences，按服务器地址隔离，换 NAS 不复用旧服务器的数据。
仅前台轮询：处理中的照片约 4 秒，已完成的日期约 5 分钟；恢复前台会刷新。
断网保留缓存，未配置识别时不生成示例作业。

交互规格见 ../../docs/04-电视端UI.md，构建矩阵见 ../../docs/06-构建环境.md。
