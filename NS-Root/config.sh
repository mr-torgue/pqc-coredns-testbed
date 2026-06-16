#!/bin/bash

DATE_TIME=$(date +"%Y%m%d-%H%M%S")

DSSET="dsset-test."
DOMAIN="."
TLS_DS="rsa:2048"
DNSSEC_DS="P256_FALCON512"
ZONEFILE="db.root"
CONFIG_NAME="config"

while getopts "d:t:a:z:n:" opt; do
  case $opt in
    d) DSSET="$OPTARG" ;;
    t) TLS_DS="$OPTARG" ;;
    a) DNSSEC_DS="$OPTARG" ;;
    z) ZONEFILE="$OPTARG" ;;
    n) CONFIG_NAME="$OPTARG" ;;
    *) echo "Usage: $0 [-d <dsset>] [-t <tls_ds>] [-a <dnssec_ds>] [-z <zonefile>]" >&2; exit 1 ;;
  esac
done

CONFIG_DIR="${CONFIG_NAME}-${DATE_TIME}"
mkdir -p "${CONFIG_DIR}"


../scripts/genkey.sh -f "${DOMAIN}" -t "${TLS_DS}" -d "${DNSSEC_DS}" 
../scripts/signzone.sh -z "${ZONEFILE}" -f "${DOMAIN}" -d "${DSSET}"


# copy files
mv K.* ${CONFIG_DIR}
cp CoreFile ${CONFIG_DIR}
cp db.root ${CONFIG_DIR}
mv db.root.signed ${CONFIG_DIR}
mv dsset-. ${CONFIG_DIR}
mv ${DSSET} ${CONFIG_DIR}
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

echo "Don't forget to change the IP addresses in the db file!!"