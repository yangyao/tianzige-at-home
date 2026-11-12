# NAS 安装

来源：上级 hearth-tv-launcher/deploy/nas-service.sh 的用户级常驻服务方式。
本应用独立目录、端口和 PID 文件，不修改已有照片服务。运行时不需要 Go、Docker、SQLite 动态库或 tzdata。

1. NAS 上运行 uname -m：aarch64 用 arm64 包，x86_64 用 amd64 包。
2. 解压对应 tianzige-nas-linux-ARCH.tar.gz，将包内内容放入独立目录，例如：

   $HOME/.local/share/tianzige-at-home/

   目录内应直接包含 bin/、web/、nas-service.sh。

3. 将 server.env.example 复制为 server.env，chmod 600 server.env。
   把 TIANZIGE_LISTEN 改成 NAS 实际局域网 IP 与未占用端口，例如 192.168.1.50:18086。
   默认 127.0.0.1 仅供本机测试；不要使用 QNAP 管理端口。
4. 若采用不同安装位置，export TIANZIGE_APP_DIR=/你的绝对路径。
5. sh "$TIANZIGE_APP_DIR/nas-service.sh" start；未指定目录时使用默认位置执行脚本。
6. 浏览器打开 http://NAS地址:端口/，三个客户端设置同一地址。

status、stop、restart 使用同一个脚本。先用 curl 检查 /api/health，响应应为 ok:true。
没有配置识别时 ocr:unconfigured，图片照常上传、保存和在电视查看，文字不伪造。
要识别文字，在 server.env 配置自己的已有 vision 服务地址、密钥、模型，TIANZIGE_OCR=openai；
TIANZIGE_LLM=openai 可同时启用分科。密钥只放服务器，chmod 600，不进入仓库。

本包没有注册 QPKG，也没有替 NAS 开启自启动。确认实际运行后，可通过 NAS 已有的启动机制调用 start。
更新时先 stop，备份 bin/homework-server，替换二进制与 web，再 start。保留 data/ 和 server.env。
回滚时同样停止后换回旧二进制；备份数据应在停机状态完整复制 data/（含数据库和图片）。

本机构建：在仓库 services/homework-server 下 make bundle（实际 NAS 为 arm64）。
可选 amd64 构建需已有 Go 1.21+，运行 make bundle-amd64 GO=/实际/go路径。
二进制使用 CGO_ENABLED=0、GOOS=linux，与上级已验证服务保持一致。
2026-11-12 已在实际 Linux aarch64 NAS 完成启动、重启、上传、去重、原图比对和 Z.AI 识别分科。
本包目前为用户级常驻服务，不包含 NAS 重启后的 QPKG 自动启动注册。
AI 的密钥文件与模型配置见 ../docs/07-AI配置.md。
