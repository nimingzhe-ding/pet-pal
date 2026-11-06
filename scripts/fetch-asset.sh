#!/bin/bash
# 获取并准备鲸鱼娘形象素材
#
# 素材来源：DeepSeek娘表情包开源合集（非营利粉丝向）
#   https://github.com/the-beating-light-of-the-nail/deepseek-chan-meme-pack
#
# 角色形象「蓝色大肥鱼 / 鲸鱼娘」版权归原作者及社区创作者所有。
# 本项目仅作个人桌面摆件使用，不随仓库分发该图片。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$ROOT/assets"
mkdir -p "$ASSETS"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ 下载素材..."
curl -fsSL -o "$TMP/010.webp" \
  "https://raw.githubusercontent.com/the-beating-light-of-the-nail/deepseek-chan-meme-pack/main/previews/010.webp"

echo "→ 转成 PNG..."
sips -s format png "$TMP/010.webp" --out "$TMP/010.png" >/dev/null

echo "→ 编译抠图工具..."
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo "")
if [[ -n "$SDK" ]]; then
  swiftc -O -sdk "$SDK" "$ROOT/tools/cutout.swift" -o "$TMP/cutout" 2>/dev/null \
    || swiftc -O "$ROOT/tools/cutout.swift" -o "$TMP/cutout"
else
  swiftc -O "$ROOT/tools/cutout.swift" -o "$TMP/cutout"
fi

echo "→ 抠图（白底转透明，去掉底部文字）..."
"$TMP/cutout" "$TMP/010.png" "$ASSETS/whale.png" 20 0 482 372 236

echo "✓ 完成: $ASSETS/whale.png"
echo
echo "  素材版权归原作者所有，请勿用于商业用途。"
