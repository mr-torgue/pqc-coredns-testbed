#!/bin/bash
DATE_TIME=$(date +"%Y%m%d-%H%M%S")
CONFIG_DIR="config-${DATE_TIME}"
mkdir -p "${CONFIG_DIR}"

DSSET="dsset-."
OUTPUT_FILE="${CONFIG_DIR}/trust-anchors.xml"

if [ -f "$DSSET" ]; then
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
else
    echo "DS file not found: $DSSET"
fi
