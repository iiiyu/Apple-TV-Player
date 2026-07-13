#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$PWD}"
SQUARE_MASTER="${1:-$ROOT_DIR/AppStoreAssets/brand/iptv-app-icon-master.png}"
LANDSCAPE_MASTER="${2:-$ROOT_DIR/AppStoreAssets/brand/iptv-tvos-master.png}"
ASSET_ROOT="$ROOT_DIR/AppleTVMultiplatform/Resources/Assets.xcassets"
APP_ICON_DIR="$ASSET_ROOT/AppIcon.appiconset"
TV_DIR="$ASSET_ROOT/App Icon & Top Shelf Image.brandassets"

if [[ ! -f "$SQUARE_MASTER" ]]; then
  echo "Missing square icon master: $SQUARE_MASTER" >&2
  exit 1
fi

if [[ ! -f "$LANDSCAPE_MASTER" ]]; then
  echo "Missing tvOS landscape master: $LANDSCAPE_MASTER" >&2
  exit 1
fi

resize_square() {
  local size="$1"
  local output="$2"

  rtk magick "$SQUARE_MASTER" \
    -filter Lanczos \
    -resize "${size}x${size}!" \
    -alpha off \
    -strip \
    "PNG24:$output"
}

make_tvos_front() {
  local width="$1"
  local height="$2"
  local output="$3"

  rtk magick "$LANDSCAPE_MASTER" \
    -filter Lanczos \
    -resize "${width}x${height}^" \
    -gravity center \
    -extent "${width}x${height}" \
    \( +clone -colorspace Gray -level 5%,24% \) \
    -alpha off \
    -compose CopyOpacity \
    -composite \
    -strip \
    "$output"
}

make_tvos_back() {
  local width="$1"
  local height="$2"
  local blur="$3"
  local output="$4"

  rtk magick "$LANDSCAPE_MASTER" \
    -filter Lanczos \
    -resize "${width}x${height}^" \
    -gravity center \
    -extent "${width}x${height}" \
    -blur "0x${blur}" \
    -modulate 58,90,100 \
    -alpha off \
    -strip \
    "PNG24:$output"
}

make_tvos_base() {
  local width="$1"
  local height="$2"
  local output="$3"

  rtk magick -size "${width}x${height}" \
    "gradient:#010229-#020b3c" \
    -alpha off \
    -strip \
    "PNG24:$output"
}

make_top_shelf() {
  local width="$1"
  local height="$2"
  local output="$3"

  rtk magick \
    \( "$LANDSCAPE_MASTER" -filter Lanczos -resize "${width}x${height}!" -blur "0x$((height / 20))" -modulate 45,85,100 \) \
    \( "$LANDSCAPE_MASTER" -filter Lanczos -resize "x${height}" \) \
    -gravity center \
    -compose Over \
    -composite \
    -alpha off \
    -strip \
    "PNG24:$output"
}

resize_square 1024 "$APP_ICON_DIR/ios-appicon-1024.png"
resize_square 16 "$APP_ICON_DIR/mac-appicon-16.png"
resize_square 32 "$APP_ICON_DIR/mac-appicon-16@2x.png"
resize_square 32 "$APP_ICON_DIR/mac-appicon-32.png"
resize_square 64 "$APP_ICON_DIR/mac-appicon-32@2x.png"
resize_square 128 "$APP_ICON_DIR/mac-appicon-128.png"
resize_square 256 "$APP_ICON_DIR/mac-appicon-128@2x.png"
resize_square 256 "$APP_ICON_DIR/mac-appicon-256.png"
resize_square 512 "$APP_ICON_DIR/mac-appicon-256@2x.png"
resize_square 512 "$APP_ICON_DIR/mac-appicon-512.png"
resize_square 1024 "$APP_ICON_DIR/mac-appicon-512@2x.png"

make_tvos_front 1280 768 "$TV_DIR/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/AppIcon-AppStore-Front@1280x768.png"
make_tvos_back 1280 768 32 "$TV_DIR/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/AppIcon-AppStore-Back@1280x768.png"
make_tvos_base 1280 768 "$TV_DIR/App Icon - App Store.imagestack/Base.imagestacklayer/Content.imageset/AppIcon-AppStore-Base@1280x768.png"

make_tvos_front 400 240 "$TV_DIR/App Icon.imagestack/Front.imagestacklayer/Content.imageset/AppIcon-Front@400x240.png"
make_tvos_front 800 480 "$TV_DIR/App Icon.imagestack/Front.imagestacklayer/Content.imageset/AppIcon-Front@800x480.png"
make_tvos_back 400 240 10 "$TV_DIR/App Icon.imagestack/Back.imagestacklayer/Content.imageset/AppIcon-Back@400x240.png"
make_tvos_back 800 480 20 "$TV_DIR/App Icon.imagestack/Back.imagestacklayer/Content.imageset/AppIcon-Back@800x480.png"
make_tvos_base 400 240 "$TV_DIR/App Icon.imagestack/Base.imagestacklayer/Content.imageset/AppIcon-Base@400x240.png"
make_tvos_base 800 480 "$TV_DIR/App Icon.imagestack/Base.imagestacklayer/Content.imageset/AppIcon-Base@800x480.png"

make_top_shelf 1920 720 "$TV_DIR/Top Shelf Image.imageset/AppIcon-TopShelf@1920x720.png"
make_top_shelf 3840 1440 "$TV_DIR/Top Shelf Image.imageset/AppIcon-TopShelf@3840x1440.png"
make_top_shelf 2320 720 "$TV_DIR/Top Shelf Image Wide.imageset/AppIcon-TopShelf-Wide@2320x720.png"
make_top_shelf 4640 1440 "$TV_DIR/Top Shelf Image Wide.imageset/AppIcon-TopShelf-Wide@4640x1440.png"

echo "Brand assets generated from:"
echo "  $SQUARE_MASTER"
echo "  $LANDSCAPE_MASTER"
