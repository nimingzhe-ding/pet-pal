#!/bin/bash
# 编译并安装鲸鱼娘桌宠
#
#   ./scripts/build.sh            只编译
#   ./scripts/build.sh --install  编译并安装到 ~/.claude/pet-desktop/bin

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/pet"

# 选一个和编译器匹配的 SDK —— xcrun 可能返回比编译器更新的版本
pick_sdk() {
  local compiler_ver
  compiler_ver=$(swiftc --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)

  for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk; do
    [[ -d "$sdk" ]] || continue
    # 读 SDK 里 swiftinterface 的编译器版本
    local iface="$sdk/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
    [[ -f "$iface" ]] || continue
    local sdk_ver
    sdk_ver=$(grep -m1 'swift-compiler-version' "$iface" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [[ "$sdk_ver" == "$compiler_ver" ]]; then
      echo "$sdk"
      return
    fi
  done
  echo ""
}

SDK=$(pick_sdk)
if [[ -z "$SDK" ]]; then
  echo "找不到与编译器匹配的 SDK，尝试默认值" >&2
  SDK=$(xcrun --show-sdk-path 2>/dev/null || echo "")
fi
echo "使用 SDK: $SDK"
if [[ -n "$SDK" ]]; then
  swiftc -O -sdk "$SDK" \
    "$ROOT/src/WhaleGirl.swift" \
    "$ROOT/src/SessionPanel.swift" \
    "$ROOT/src/SessionReader.swift" \
    "$ROOT/src/SessionJump.swift" \
    "$ROOT/src/main.swift" \
    -o "$OUT"
else
  swiftc -O \
    "$ROOT/src/WhaleGirl.swift" \
    "$ROOT/src/SessionPanel.swift" \
    "$ROOT/src/SessionReader.swift" \
    "$ROOT/src/SessionJump.swift" \
    "$ROOT/src/main.swift" \
    -o "$OUT"
fi

echo "✓ 编译完成: $OUT"

if [[ "${1:-}" == "--install" ]]; then
  INSTALL_DIR="$HOME/.claude/pet-desktop"
  mkdir -p "$INSTALL_DIR/bin/assets"

  if [[ ! -f "$ROOT/assets/whale.png" ]]; then
    echo "素材不存在，先运行 scripts/fetch-asset.sh" >&2
    exit 1
  fi

  # 先停掉在跑的实例，否则覆盖二进制会失败
  pkill -f "pet-desktop/bin/petpal" 2>/dev/null || true
  sleep 0.5

  cp "$OUT" "$INSTALL_DIR/bin/petpal"
  chmod +x "$INSTALL_DIR/bin/petpal"
  cp "$ROOT/assets/whale.png" "$INSTALL_DIR/bin/assets/whale.png"
  cp "$ROOT/petpal" "$INSTALL_DIR/petpal"
  cp -R "$ROOT/src" "$ROOT/scripts" "$ROOT/tools" "$INSTALL_DIR/"

  echo "✓ 已安装到 $INSTALL_DIR"
  echo "  用 petpal on 启动"
fi
