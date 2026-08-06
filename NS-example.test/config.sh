#!/bin/bash

DATE_TIME=$(date +"%Y%m%d-%H%M%S")

TLS_DS="ED25519"
DNSSEC_DS_LIST=("FALCON512" "P256_FALCON512" "RSA3072_FALCON512" "FALCON1024" "P521_FALCON1024" "MLDSA44" "P256_MLDSA44" "RSA3072_MLDSA44" "SLHDSASHA2128S" "P256_SLHDSASHA2128S" "RSA3072_SLHDSASHA2128S" "MAYO1" "P256_MAYO1" "SNOVA2454" "P256_SNOVA2454" "ECDSAP256SHA256" "ED25519" "NA") 
CONFIG_NAME="config"

while getopts "t:a:l:i:n:" opt; do
	case $opt in
		t) TLS_DS="$OPTARG" ;;
		a) DNSSEC_DS_LIST=("$OPTARG") ;;
		l) LOC="$OPTARG" ;;
		i) NS_IP="$OPTARG" ;;
		n) CONFIG_NAME="$OPTARG" ;;
		*) echo "Usage: $0 [-d <dsset>] [-t <tls_ds>] [-a <dnssec_ds>] [-l <location>] [-i <ns_ip>] [-n <config_name>]" >&2; exit 1 ;;
	esac
done

# check
if [ -z "$LOC" ] || [ -z "$NS_IP" ]; then
	echo "Error: Both location and NS IP must be set" >&2
	exit 1
fi

CONFIG_DIR="${CONFIG_NAME}-${LOC}-${DATE_TIME}"
mkdir -p "${CONFIG_DIR}"

DOMAINS=()
IMPORT_SCRIPT=""
for DNSSEC_DS in "${DNSSEC_DS_LIST[@]}"; do
    # generate zone file
    DOMAIN=$(echo "${DNSSEC_DS}-${LOC}.test" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    ZONEFILE="db.${DOMAIN}"
    ../scripts/genzone.sh -f "$DOMAIN" -i "$NS_IP" -n 1000 -w > $ZONEFILE

    if [ "$DNSSEC_DS" != "NA" ]; then
      	../scripts/gendnskey.sh -f "${DOMAIN}" -d "${DNSSEC_DS}"
		../scripts/signzone.sh -z "$ZONEFILE" -f "${DOMAIN}"

		# export DS record for easy import
		DSRR="dsset-${DOMAIN}."
		if [ ! -f "$DSRR" ]; then
			echo "Error: File '$DOMAIN' not found." >&2
			exit 1
		fi
		checksum=$(sha256sum "$DSRR" | awk '{print $1}')

		# import into a variable
		read -r -d '' NEW_BLOCK <<EOF
cat > $DSRR << 'INNER_EOF'
$(cat "$DSRR")
INNER_EOF
echo '$checksum  $DSRR' | sha256sum --check
if grep -q "ns1.${DOMAIN}.\s*IN\s*NS" db.test; then
    sed -i "/ns1.${DOMAIN}.\s*IN\s*A/c ns1.${DOMAIN}.	IN	A	${NS_IP}" db.test
else
    echo "${DOMAIN}.	IN	NS	ns1.${DOMAIN}." >> db.test
    echo "ns1.${DOMAIN}.	IN	A	${NS_IP}" >> db.test
fi
EOF
		IMPORT_SCRIPT+="$NEW_BLOCK"

		# copy dnssec files
		mv K${DOMAIN}* ${CONFIG_DIR}
		mv db.${DOMAIN} ${CONFIG_DIR}
		mv db.${DOMAIN}.signed ${CONFIG_DIR}
		mv $DSRR ${CONFIG_DIR}
    fi
    DOMAINS+=("$DOMAIN")
done

# generate a TLS certificate
../scripts/gentlskey.sh -f "${DOMAINS}" -t "${TLS_DS}"

# copy files
cp CoreFile ${CONFIG_DIR}
mv key.pem ${CONFIG_DIR}
mv cert.pem ${CONFIG_DIR}

# print import script
echo "Import script for .test nameserver:"
echo "$IMPORT_SCRIPT"

cat > "${CONFIG_DIR}/config.json" <<EOF
{
	"domains": "${DOMAINS}",
	"TLS Signature Scheme": "${TLS_DS}",
	"DNSSEC Algorithm": "${DNSSEC_DS}",
	"Config Directory": "${CONFIG_DIR}",
	"Date": "${DATE_TIME}",
	"Config Name": "${CONFIG_NAME}"
}
EOF