#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
command -v rsvg-convert >/dev/null || { echo "Use the existing librsvg rsvg-convert tool" >&2; exit 1; }
command -v magick >/dev/null || { echo "Use the existing ImageMagick tool" >&2; exit 1; }
mkdir -p "$ROOT/design/icons" "$ROOT/apps/upload-web/assets"
rsvg-convert -w 1024 -h 1024 "$ROOT/design/app-icon.svg" -o "$ROOT/design/icons/app-icon-1024.png"
rsvg-convert -w 320 -h 180 "$ROOT/design/app-icon-banner.svg" -o "$ROOT/apps/tv-android/app/src/main/res/drawable-nodpi/tv_banner.png"
for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density=${spec%:*}
  size=${spec#*:}
  mkdir -p "$ROOT/apps/tv-android/app/src/main/res/mipmap-$density"
  rsvg-convert -w "$size" -h "$size" "$ROOT/design/app-icon.svg" -o "$ROOT/apps/tv-android/app/src/main/res/mipmap-$density/ic_launcher.png"
done
for platform in ios mac tv-mac; do
  case "$platform" in
    ios) ASSETS="$ROOT/apps/upload-ios/Tianzige/Assets.xcassets";;
    mac) ASSETS="$ROOT/apps/upload-mac/Assets.xcassets";;
    tv-mac) ASSETS="$ROOT/apps/tv-mac/Assets.xcassets";;
  esac
  mkdir -p "$ASSETS/BrandMark.imageset"
  cp "$ROOT/design/icons/app-icon-1024.png" "$ASSETS/BrandMark.imageset/brand.png"
  cat > "$ASSETS/BrandMark.imageset/Contents.json" <<'JSON'
{"images":[{"filename":"brand.png","idiom":"universal"}],"info":{"author":"xcode","version":1}}
JSON
done
magick "$ROOT/design/icons/app-icon-1024.png" -background '#3E7A5E' -alpha remove -alpha off "$ROOT/apps/upload-ios/Tianzige/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
cp "$ROOT/design/icons/app-icon-1024.png" "$ROOT/apps/upload-web/assets/brand.png"
python3 - "$ROOT" <<'PY'
import json, subprocess, sys
from pathlib import Path
root = Path(sys.argv[1])
dests = [
    root/'apps/upload-mac/Assets.xcassets/AppIcon.appiconset',
    root/'apps/tv-mac/Assets.xcassets/AppIcon.appiconset',
]
for dest in dests:
    dest.mkdir(parents=True, exist_ok=True)
    images = []
    for size in (16,32,128,256,512):
        for scale in (1,2):
            name = f'icon-{size}@{scale}x.png'
            subprocess.run(['magick',str(root/'design/icons/app-icon-1024.png'),'-resize',f'{size*scale}x{size*scale}',str(dest/name)],check=True)
            images.append(dict(filename=name,idiom='mac',size=f'{size}x{size}',scale=f'{scale}x'))
    (dest/'Contents.json').write_text(json.dumps(dict(images=images,info=dict(author='xcode',version=1)),indent=2)+'\n')
PY
