#!/bin/bash

DATE_TIME=$(date +"%Y%m%d-%H%M%S")

DOMAIN="."
TLS_DS="rsa:2048"
DNSSEC_DS="P256_FALCON512"
ZONEFILE="db.root"
CONFIG_NAME="config"

while getopts "t:a:z:n:" opt; do
  case $opt in
    t) TLS_DS="$OPTARG" ;;
    a) DNSSEC_DS="$OPTARG" ;;
    z) ZONEFILE="$OPTARG" ;;
    n) CONFIG_NAME="$OPTARG" ;;
    *) echo "Usage: $0 [-t <tls_ds>] [-a <dnssec_ds>] [-z <zonefile>]" >&2; exit 1 ;;
  esac
done

CONFIG_DIR="${CONFIG_NAME}-${DATE_TIME}"
mkdir -p "${CONFIG_DIR}"


../scripts/gendnskey.sh -f "${DOMAIN}" -d "${DNSSEC_DS}"
../scripts/gentlskey.sh -f "${DOMAIN}" -t "${TLS_DS}"
../scripts/signzone.sh -z "${ZONEFILE}" -f "${DOMAIN}"

# export DS record for easy import
DSRR="dsset-."
if [ ! -f "$DSRR" ]; then
    echo "Error: File '$file' not found." >&2
    exit 1
fi

checksum=$(sha256sum "$DSRR" | awk '{print $1}')

echo "cat > $DSRR << 'EOF'"
cat "$DSRR"
echo "EOF"
echo "echo '$checksum  $DSRR' | sha256sum --check"

# copy files
mv K.* ${CONFIG_DIR}
cp CoreFile ${CONFIG_DIR}
cp db.root ${CONFIG_DIR}
mv db.root.signed ${CONFIG_DIR}
mv dsset* ${CONFIG_DIR}
mv key.pem ${CONFIG_DIR}
mv cert.pem ${CONFIG_DIR}


cat > "${CONFIG_DIR}/config.json" <<EOF
{
  "domain": "${DOMAIN}",
  "TLS Signature Scheme": "${TLS_DS}",
  "DNSSEC Algorithm": "${DNSSEC_DS}",
  "Config Directory": "${CONFIG_DIR}",
  "Date": "${DATE_TIME}",
  "Config Name": "${CONFIG_NAME}"
}
EOF