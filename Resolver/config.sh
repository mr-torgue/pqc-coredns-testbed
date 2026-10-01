#!/bin/bash
DATE_TIME=$(date +"%Y%m%d-%H%M%S")

DSSET="dsset-."
TLS_DS="rsa:2048"
ZONEFILE="named.root"
CONFIG_NAME="config"
ROOT_ANCHOR=""

while getopts "d:t:z:c:r:" opt; do
  case $opt in
    d) DSSET="$OPTARG" ;;
    t) TLS_DS="$OPTARG" ;;
    z) ZONEFILE="$OPTARG" ;;
    c) CONFIG_NAME="$OPTARG" ;;
    r) ROOT_ANCHOR="$OPTARG" ;;
    *) echo "Usage: $0 [-d <dsset>] [-t <tls_ds>] [-z <zonefile>] [-c <config file>] [-r <root anchor XML file>]" >&2; exit 1 ;;
  esac
done

if [ -z "$DSSET" ] && [ -z "$ROOT_ANCHOR" ]; then
    echo "Error: Either -d (DSSET) or -r (root anchor XML file) must be provided" >&2
    exit 1
fi

CONFIG_DIR="${CONFIG_NAME}-${DATE_TIME}"
mkdir -p "${CONFIG_DIR}"
OUTPUT_FILE="${CONFIG_DIR}/trust-anchors.xml"
if [ ! -f "$ZONEFILE" ]; then
    echo "Error: The specified root zone file does not exist" >&2
    exit 1
fi

if [ -n "$ROOT_ANCHOR" ]; then
    if [ ! -f "$ROOT_ANCHOR" ]; then
        echo "Error: The specified root anchor XML file does not exist" >&2
        exit 1
    fi
    cp "$ROOT_ANCHOR" "$OUTPUT_FILE"
    echo "Copied root anchor XML file: $ROOT_ANCHOR"
elif [ -f "$DSSET" ]; then
    echo "Found DS file: $DSSET"
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" > "$OUTPUT_FILE"
    echo "<TrustAnchor>" >> "$OUTPUT_FILE"

    count=0
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*[.][[:space:]]+IN[[:space:]]+DS[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+(.*) ]]; then
            keytag=${BASH_REMATCH[1]}
            algorithm=${BASH_REMATCH[2]}
            digesttype=${BASH_REMATCH[3]}
            digest=$(echo "${BASH_REMATCH[4]}" | tr -d ' ')
            id=$(openssl rand -hex 4)

            echo "    <KeyDigest id=\"$id\" validFrom=\"$(date +%Y-%m-%dT%H:%M:%S+00:00)\" validUntil=\"2035-01-01T00:00:00+00:00\">" >> "$OUTPUT_FILE"
            echo "        <KeyTag>$keytag</KeyTag>" >> "$OUTPUT_FILE"
            echo "        <Algorithm>$algorithm</Algorithm>" >> "$OUTPUT_FILE"
            echo "        <DigestType>$digesttype</DigestType>" >> "$OUTPUT_FILE"
            echo "        <Digest>$digest</Digest>" >> "$OUTPUT_FILE"
            echo "    </KeyDigest>" >> "$OUTPUT_FILE"
            ((count++))
        fi
    done < "$DSSET"

    echo "</TrustAnchor>" >> "$OUTPUT_FILE"
    echo "Found $count entries in DS file."
    mv ${DSSET} ${CONFIG_DIR}
else
    echo "DS file not found: $DSSET"
    exit 1
fi

# generate TLS key
sudo openssl req -x509 -nodes -days 365 -newkey ${TLS_DS} -keyout key.pem -out cert.pem -subj "/CN=resolver"

# copy files
cp CoreFile ${CONFIG_DIR}
cp $ZONEFILE ${CONFIG_DIR}/named.root
mv key.pem ${CONFIG_DIR}
mv cert.pem ${CONFIG_DIR}

jq -n \
    --arg tls_ds "$TLS_DS" \
    --arg config_dir "$CONFIG_DIR" \
    --arg date_time "$DATE_TIME" \
    --arg config_name "$CONFIG_NAME" \
    '{
        "TLS Signature Scheme": $tls_ds,
        "Config Directory": $config_dir,
        "Date": $date_time,
        "Config Name": $config_name
    }' > "${CONFIG_DIR}/config.json"
    


cat > "${CONFIG_DIR}/coredns.service" <<EOF
[Unit]
Description=CoreDNS DNS server
Documentation=https://coredns.io
After=network.target

[Service]
LimitNOFILE=1048576
LimitNPROC=512
WorkingDirectory=$(pwd)/${CONFIG_DIR}
ExecStart=/opt/coredns/coredns -conf=$(pwd)/${CONFIG_DIR}/CoreFile
ExecReload=/bin/kill -SIGUSR1 $MAINPID
Restart=on-failure
StandardOutput=append:/var/log/coredns.log
StandardError=append:/var/log/coredns.err.log

[Install]
WantedBy=multi-user.target
EOF
