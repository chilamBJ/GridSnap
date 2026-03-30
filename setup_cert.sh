#!/bin/bash
set -euo pipefail
cd /tmp

cat > gs_cert.cfg <<'EOF'
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

openssl req -x509 -newkey rsa:2048 \
    -keyout gs_key.pem -out gs_cert.pem \
    -days 3650 -nodes \
    -config gs_cert.cfg -extensions v3_code_sign

openssl pkcs12 -export \
    -out gs_bundle.p12 \
    -inkey gs_key.pem -in gs_cert.pem \
    -name "GridSnap Dev" \
    -passout pass:tmp123

security import gs_bundle.p12 \
    -k ~/Library/Keychains/login.keychain-db \
    -P "tmp123" \
    -T /usr/bin/codesign \
    -f pkcs12

echo "=== 导入完成 ==="

security find-certificate -c "GridSnap Dev" ~/Library/Keychains/login.keychain-db | head -5

security add-trusted-cert -d -r trustRoot -p codeSign \
    -k ~/Library/Keychains/login.keychain-db \
    gs_cert.pem

echo "=== 信任设置完成 ==="

security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "" ~/Library/Keychains/login.keychain-db 2>/dev/null || true

echo "=== 可用签名身份 ==="
security find-identity -v -p codesigning

rm -f gs_key.pem gs_cert.pem gs_bundle.p12 gs_cert.cfg
