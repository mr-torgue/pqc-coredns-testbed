#!/bin/bash

DATE_TIME=$(date +"%Y%m%d-%H%M%S")

TLS_DS="rsa:2048"
DNSSEC_DS_LIST=("FALCON512" "P256_FALCON512" "DILITHIUM2" "P256_DILITHIUM" "SPHICS" "P256_SPHINCS" "P256" "NA")
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
    DOMAIN="${DNSSEC_DS}-${LOC}.test"
    ZONEFILE="db.${DNSSEC_DS}-${LOC}.test"
    ../scripts/genzone.sh -a "$DNSSEC_DS" -l "$LOC" -i "$NS_IP" -n 1000 -w > $ZONEFILE

    if [ "$DNSSEC_DS" != "NA" ]; then
      	../scripts/gendnskey.sh -f "${DOMAIN}" -d "${DNSSEC_DS}"
		../scripts/signzone.sh -z "$ZONEFILE" -f "${DOMAIN}"

		# export DS record for easy import
		DSRR="dsset-${DOMAIN}."
		if [ ! -f "$DSRR" ]; then
			echo "Error: File '$file' not found." >&2
			exit 1
		fi
		checksum=$(sha256sum "$DSRR" | awk '{print $1}')

		# verifies DSSET on .test NS
		IMPORT_SCRIPT+=$(echo "cat > $DSRR << 'EOF'\n")
		IMPORT_SCRIPT+=$(cat "$DSRR")
		IMPORT_SCRIPT+=$(echo "EOF")
		IMPORT_SCRIPT+=$(echo "echo '$checksum  $DSRR' | sha256sum --check")

		# changes the NS and A record on the .test NS
		IMPORT_SCRIPT+=$(echo "if grep -q \"ns1.${DOMAIN}.\s*IN\s*NS\" db.test; then\n")
		IMPORT_SCRIPT+=$(echo "    sed -i \"/ns1.${DOMAIN}.\s*IN\s*A/c ns1.${DOMAIN}.	IN	A	${NS_IP}\" db.test\n")
		IMPORT_SCRIPT+=$(echo "else\n")
		IMPORT_SCRIPT+=$(echo "    echo \"ns1.${DOMAIN}.	IN	NS	ns1.${DOMAIN}.\" >> db.test\n")
		IMPORT_SCRIPT+=$(echo "    echo \"ns1.${DOMAIN}.	IN	A	${NS_IP}\" >> db.test\n")
		IMPORT_SCRIPT+=$(echo "fi\n")

		# copy dnssec files
		mv K{$DOMAIN}* ${CONFIG_DIR}
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