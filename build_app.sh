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


# 5. 检查/创建自签名证书（让 TCC 权限在重编译后持续有效）
CERT_NAME="GridSnap Dev"
if ! security find-identity -v -p codesigning login.keychain 2>/dev/null | grep -q "$CERT_NAME"; then
    echo ""
    echo "→ 首次构建：创建自签名代码签名证书..."
    echo "  ⚠️  请在弹出的「钥匙串访问」窗口中输入密码"

    # 用 Keychain Access 脚本创建自签名证书
    osascript -e '
    tell application "Keychain Access"
        -- noop to trigger launch
    end tell' 2>/dev/null || true

    # 通过 security 命令创建
    cat > /tmp/gs_cert.cfg <<CERTEOF
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
[ req_dn ]
CN = GridSnap Dev
[ v3_code_sign ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
CERTEOF

    openssl req -x509 -newkey rsa:2048 \
        -keyout /tmp/gs_key.pem -out /tmp/gs_cert.pem \
        -days 3650 -nodes \
        -config /tmp/gs_cert.cfg -extensions v3_code_sign 2>/dev/null

    openssl pkcs12 -export \
        -out /tmp/gs.p12 \
        -inkey /tmp/gs_key.pem -in /tmp/gs_cert.pem \
        -passout pass:gridsnap 2>/dev/null

    security import /tmp/gs.p12 -k ~/Library/Keychains/login.keychain-db \
        -P "gridsnap" -T /usr/bin/codesign 2>/dev/null || \
    security import /tmp/gs.p12 -k ~/Library/Keychains/login.keychain \
        -P "gridsnap" -T /usr/bin/codesign 2>/dev/null || true

    # 设置分区列表，允许 codesign 无弹窗使用
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "" ~/Library/Keychains/login.keychain-db 2>/dev/null || true

    rm -f /tmp/gs_key.pem /tmp/gs_cert.pem /tmp/gs.p12 /tmp/gs_cert.cfg

    echo "  ✓ 证书已创建"
    echo ""
    echo "  ⚠️  首次使用需手动信任证书："
    echo "     打开「钥匙串访问」→ 登录 → 证书 → 双击「GridSnap Dev」"
    echo "     → 信任 → 代码签名 → 始终信任"
fi

# 6. 代码签名（优先用自签名证书，fallback 到 ad-hoc）
echo "→ 代码签名..."
# 清理 resource fork / .DS_Store，防止 codesign 报错
find "${APP_BUNDLE}" -name '._*' -delete 2>/dev/null || true
find "${APP_BUNDLE}" -name '.DS_Store' -delete 2>/dev/null || true
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    codesign --force --deep --sign "$CERT_NAME" \
        --entitlements "${SCRIPT_DIR}/GridSnap.entitlements" \
        "${APP_BUNDLE}" 2>&1
    echo "✓ 代码签名完成 (自签名证书: $CERT_NAME)"
else
    codesign --force --deep --sign - \
        --entitlements "${SCRIPT_DIR}/GridSnap.entitlements" \
        "${APP_BUNDLE}" 2>&1
    echo "✓ 代码签名完成 (ad-hoc)"
    echo "  ⚠️  ad-hoc 签名：每次重编译后需重新授予权限"
fi

# 7. 验证
echo ""
echo "=== 打包完成 ==="
echo "  📦 ${APP_BUNDLE}"
echo "  大小: $(du -sh "${APP_BUNDLE}" | cut -f1)"
echo ""
echo "安装方式:"
echo "  1. 直接双击运行: open ${APP_BUNDLE}"
echo "  2. 拖到 /Applications 安装: cp -R ${APP_BUNDLE} /Applications/"
echo ""
echo "  首次安装后需要授予:"
echo "  → 系统设置 → 隐私与安全性 → 辅助功能 → 添加/勾选 GridSnap"
echo "  → 系统设置 → 隐私与安全性 → 屏幕录制 → 添加/勾选 GridSnap"

