#!/bin/bash
# 创建自签名代码签名证书 — 让 TCC 权限在重编译后持续有效
set -euo pipefail

CERT_NAME="GridSnap Dev"

# 检查证书是否已存在
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✅ 证书 '$CERT_NAME' 已存在"
    exit 0
fi

echo "→ 正在创建自签名代码签名证书 '$CERT_NAME' ..."
echo "  (可能需要输入钥匙串密码)"

# 创建证书配置
cat > /tmp/gridsnap_cert.cfg <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
[ req_dn ]
CN = GridSnap Dev
[ v3_code_sign ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

# 生成自签名证书
openssl req -x509 -newkey rsa:2048 \
    -keyout /tmp/gridsnap_key.pem \
    -out /tmp/gridsnap_cert.pem \
    -days 3650 -nodes \
    -config /tmp/gridsnap_cert.cfg \
    -extensions v3_code_sign 2>/dev/null

# 打包为 p12
openssl pkcs12 -export \
    -out /tmp/gridsnap.p12 \
    -inkey /tmp/gridsnap_key.pem \
    -in /tmp/gridsnap_cert.pem \
    -passout pass: 2>/dev/null

# 导入到钥匙串并信任
security import /tmp/gridsnap.p12 -k ~/Library/Keychains/login.keychain-db -P "" -T /usr/bin/codesign 2>/dev/null || \
security import /tmp/gridsnap.p12 -k ~/Library/Keychains/login.keychain -P "" -T /usr/bin/codesign 2>/dev/null

# 设置 ACL 允许 codesign 使用（免密码弹窗）
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" ~/Library/Keychains/login.keychain-db 2>/dev/null || true

# 清理
rm -f /tmp/gridsnap_key.pem /tmp/gridsnap_cert.pem /tmp/gridsnap.p12 /tmp/gridsnap_cert.cfg

echo "✅ 证书 '$CERT_NAME' 创建成功"
echo "   有效期: 10 年"
echo ""
echo "⚠️  还需要在「钥匙串访问」中信任证书："
echo "   1. 打开「钥匙串访问」→ 登录 → 证书"
echo "   2. 双击「GridSnap Dev」→ 信任 → 代码签名 → 始终信任"
