#!/bin/bash
# GridSnap DMG 打包脚本
# 依赖 build_app.sh 先生成 GridSnap.app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="GridSnap"
VERSION="1.1.0"
APP_BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${SCRIPT_DIR}/${DMG_NAME}"
DMG_TEMP="${SCRIPT_DIR}/.build/dmg_temp"

echo "=== GridSnap DMG 打包 ==="

# 1. 确保 .app 存在
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "→ 未找到 ${APP_NAME}.app，先执行 build_app.sh..."
    bash "${SCRIPT_DIR}/build_app.sh"
fi

echo "→ 准备 DMG 内容..."
rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"

# 2. 复制 .app 到临时目录
cp -R "${APP_BUNDLE}" "${DMG_TEMP}/"

# 3. 创建 Applications 快捷方式
ln -s /Applications "${DMG_TEMP}/Applications"

# 4. 删除旧 DMG
rm -f "${DMG_PATH}"

# 5. 创建 DMG
echo "→ 生成 DMG..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${DMG_PATH}" 2>&1

# 6. 清理
rm -rf "${DMG_TEMP}"

echo ""
echo "=== DMG 打包完成 ==="
echo "  📦 ${DMG_PATH}"
echo "  大小: $(du -sh "${DMG_PATH}" | cut -f1)"
echo "  SHA-256: $(shasum -a 256 "${DMG_PATH}" | cut -d' ' -f1)"
