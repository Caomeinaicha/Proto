#!/bin/bash

set -e

CERT_DIR="/root/certificates"
mkdir -p "$CERT_DIR"

FILE_NAME="RootCA"

CA_NAME="Root CA"

PASSWORD=$(tr -dc A-Z0-9 </dev/urandom | head -c 8)

TMP_KEY="$CERT_DIR/temp.key"
TMP_P12="$CERT_DIR/temp.p12"

echo
echo "[*] Generating Root CA..."
echo

openssl genrsa -out "$TMP_KEY" 2048

openssl req -x509 -new -nodes \
    -key "$TMP_KEY" \
    -sha256 \
    -days 3650 \
    -out "$CERT_DIR/${FILE_NAME}.crt" \
    -subj "/O=Root CA/CN=${CA_NAME}"

openssl pkcs12 -export \
    -out "$TMP_P12" \
    -inkey "$TMP_KEY" \
    -in "$CERT_DIR/${FILE_NAME}.crt" \
    -password pass:"$PASSWORD"

BASE64_DATA=$(base64 -w 0 "$TMP_P12")

cat > "$CERT_DIR/${FILE_NAME}_FULL.txt" <<EOF
PASSWORD=${PASSWORD}

BASE64=${BASE64_DATA}
EOF

rm -f "$TMP_KEY"
rm -f "$TMP_P12"

echo
echo "=========================================="
echo "Done"
echo "=========================================="
echo

echo "[*] Certificate Name:"
echo "    $CA_NAME"

echo
echo "[*] Password:"
echo "    $PASSWORD"

echo
echo "[*] Output Files:"
echo "    $CERT_DIR/RootCA.crt"
echo "    $CERT_DIR/RootCA_FULL.txt"