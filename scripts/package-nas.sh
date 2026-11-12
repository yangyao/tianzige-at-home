#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for arch in "${@:-arm64}"; do
  case "$arch" in arm64|amd64) ;; *) echo "Unsupported NAS architecture" >&2; exit 1;; esac
  DEST="$ROOT/dist/nas-$arch"
  mkdir -p "$DEST/bin" "$DEST/web/assets"
  cp "$ROOT/dist/homework-server-linux-$arch" "$DEST/bin/homework-server"
  cp "$ROOT/deploy/nas-service.sh" "$DEST/"
  cp "$ROOT/deploy/server.env.example" "$DEST/"
  cp "$ROOT/deploy/README.md" "$DEST/README.md"
  cp "$ROOT/docs/07-AI配置.md" "$DEST/AI-configuration.md"
  cp "$ROOT/apps/upload-web/upload.html" "$ROOT/apps/upload-web/today.html" "$DEST/web/"
  cp "$ROOT/apps/upload-web/assets/brand.png" "$DEST/web/assets/"
  chmod +x "$DEST/bin/homework-server" "$DEST/nas-service.sh"
  COPYFILE_DISABLE=1 tar --format=ustar -czf "$ROOT/dist/tianzige-nas-linux-$arch.tar.gz" -C "$ROOT/dist" "nas-$arch"
done
