#!/bin/bash

DATE_TIME=$(date +"%Y%m%d-%H%M%S")

TLS_DS="ED25519" #"rsa:2048" "MLDSA44"
DNSSEC_DS_LIST=("MLDSA44" "P256_MLDSA44" "RSA3072_MLDSA44" "MLDSA65" "P384_MLDSA65" "MLDSA87" "P521_MLDSA87" "FALCON512" "P256_FALCON512" "RSA3072_FALCON512" "FALCON1024" "P521_FALCON1024" "SLHDSASHA2128S" "P256_SLHDSASHA2128S" "RSA3072_SLHDSASHA2128S" "MAYO1" "P256_MAYO1" "SNOVA2454" "P256_SNOVA2454" "ECDSAP256SHA256" "ED25519" "RSASHA256" "NA") 
CONFIG_NAME="config"
NR_ENTRIES=100

while getopts "t:a:l:i:c:n:" opt; do
	case $opt in
		t) TLS_DS="$OPTARG" ;;
		a) DNSSEC_DS_LIST=("$OPTARG") ;;
		l) LOC="$OPTARG" ;;
		i) NS_IP="$OPTARG" ;;
		c) CONFIG_NAME="$OPTARG" ;;
		n) NR_ENTRIES="$OPTARG" ;;
		*) echo "Usage: $0 [-t <tls_ds>] [-a <dnssec_ds>] [-l <location>] [-i <ns_ip>] [-c <config_name>] [-n <number of entries>]" >&2; exit 1 ;;
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
    ../scripts/genzone.sh -f "$DOMAIN" -i "$NS_IP" -n $NR_ENTRIES -w > $ZONEFILE

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
if grep -q "${DOMAIN}.\s*IN\s*NS" db.test; then
    sed -i "/ns1.${DOMAIN}.\s*IN\s*A/c ns1.${DOMAIN}.	IN	A	${NS_IP}" db.test
else
    echo "${DOMAIN}.	IN	NS	ns1.${DOMAIN}." >> db.test
    echo "ns1.${DOMAIN}.	IN	A	${NS_IP}" >> db.test
fi
EOF
		IMPORT_SCRIPT+="$NEW_BLOCK"

		# copy dnssec files
		mv K${DOMAIN}* ${CONFIG_DIR}
		mv db.${DOMAIN}.signed ${CONFIG_DIR}
		mv $DSRR ${CONFIG_DIR}
    fi
	mv db.${DOMAIN} ${CONFIG_DIR}
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

cat > "${CONFIG_DIR}/coredns.service" <<EOF
[Unit]
Description=CoreDNS DNS server
Documentation=https://coredns.io
After=network.target

[Service]
LimitNOFILE=1048576
LimitNPROC=512
WorkingDirectory=$(pwd)/${CONFIG_DIR}
ExecStart=/opt/coredns/coredns -conf=$(pwd)/${CONFIG_DIR}/Corefile
ExecReload=/bin/kill -SIGUSR1 $MAINPID
Restart=on-failure
StandardOutput=append:/var/log/coredns.log
StandardError=append:/var/log/coredns.err.log

[Install]
WantedBy=multi-user.target
EOF
