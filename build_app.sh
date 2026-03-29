#!/bin/bash
# GridSnap 打包脚本 — 生成 GridSnap.app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="GridSnap"
BUILD_DIR="${SCRIPT_DIR}/.build/release"
APP_BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
ICON_SRC="${SCRIPT_DIR}/Sources/GridSnap/Resources/AppIcon.png"
ICONSET_DIR="${SCRIPT_DIR}/.build/AppIcon.iconset"

echo "=== GridSnap 打包开始 ==="

# 1. Release 编译
echo "→ 编译 Release 版本..."
cd "${SCRIPT_DIR}"
swift build -c release 2>&1

EXECUTABLE="${BUILD_DIR}/${APP_NAME}"
if [ ! -f "${EXECUTABLE}" ]; then
    echo "❌ 编译失败，找不到可执行文件: ${EXECUTABLE}"
    exit 1
fi
echo "✓ 编译完成"

# 2. 生成 .icns 图标
echo "→ 生成应用图标..."
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

# 生成所有需要的尺寸
sips -z 16 16     "${ICON_SRC}" --out "${ICONSET_DIR}/icon_16x16.png"      > /dev/null 2>&1
sips -z 32 32     "${ICON_SRC}" --out "${ICONSET_DIR}/icon_16x16@2x.png"   > /dev/null 2>&1
sips -z 32 32     "${ICON_SRC}" --out "${ICONSET_DIR}/icon_32x32.png"      > /dev/null 2>&1
sips -z 64 64     "${ICON_SRC}" --out "${ICONSET_DIR}/icon_32x32@2x.png"   > /dev/null 2>&1
sips -z 128 128   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_128x128.png"    > /dev/null 2>&1
sips -z 256 256   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 256 256   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_256x256.png"    > /dev/null 2>&1
sips -z 512 512   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 512 512   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_512x512.png"    > /dev/null 2>&1
sips -z 1024 1024 "${ICON_SRC}" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null 2>&1

iconutil -c icns "${ICONSET_DIR}" -o "${SCRIPT_DIR}/.build/AppIcon.icns"
echo "✓ 图标生成完成"

# 3. 组装 .app bundle
echo "→ 组装 ${APP_NAME}.app ..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

# 复制可执行文件
cp "${EXECUTABLE}" "${MACOS}/${APP_NAME}"
chmod +x "${MACOS}/${APP_NAME}"

# 复制 Info.plist
cp "${SCRIPT_DIR}/Info.plist" "${CONTENTS}/Info.plist"

# 复制图标
cp "${SCRIPT_DIR}/.build/AppIcon.icns" "${RESOURCES}/AppIcon.icns"

# 复制 Resources 目录中的资源文件（如果有 bundle resources）
BUNDLE_RESOURCES="${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "${BUNDLE_RESOURCES}" ]; then
    cp -R "${BUNDLE_RESOURCES}" "${RESOURCES}/"
    echo "  ✓ 已复制 bundle resources"
fi

echo "✓ App bundle 组装完成"

# 4. Ad-hoc 代码签名 (辅助功能/屏幕录制权限需要签名)
echo "→ 代码签名..."
codesign --force --deep --sign - \
    --entitlements "${SCRIPT_DIR}/GridSnap.entitlements" \
    "${APP_BUNDLE}" 2>&1
echo "✓ 代码签名完成"

# 5. 重置辅助功能权限（重签名后旧授权失效）
echo ""
echo "→ 重置辅助功能权限缓存..."
tccutil reset Accessibility com.gridsnap.app 2>/dev/null || true
echo "✓ 权限缓存已重置"

# 6. 验证
echo ""
echo "=== 打包完成 ==="
echo "  📦 ${APP_BUNDLE}"
echo "  大小: $(du -sh "${APP_BUNDLE}" | cut -f1)"
echo ""
echo "安装方式:"
echo "  1. 直接双击运行: open ${APP_BUNDLE}"
echo "  2. 拖到 /Applications 安装: cp -R ${APP_BUNDLE} /Applications/"
echo ""
echo "⚠️  重要: 每次重新打包后，需要重新授予辅助功能权限！"
echo "  → 系统设置 → 隐私与安全性 → 辅助功能 → 添加/勾选 GridSnap"
echo "  （首次运行时 app 会自动弹出引导窗口）"
