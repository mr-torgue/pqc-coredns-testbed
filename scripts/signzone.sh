#!/bin/bash

usage() {
    echo "Usage: $0 -z/--zonefile <filename> [-d/--ds <filename>] [-f/--fqdn <domain>]"
    echo "Will look for DS records in files starting with dsset"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -z|--zonefile) ZONEFILE="$2"; shift ;;
        -f|--fqdn) DOMAIN="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

if [ -z "$ZONEFILE" ]; then
    echo "Error: Zone file is required."
    usage
fi

DSSET_COUNT=0
cp "$ZONEFILE" "${ZONEFILE}.tmp"
ZONEFILE="${ZONEFILE}.tmp" # always work on a temp file
for DSSET_FILE in dsset*; do
    if [ -f "$DSSET_FILE" ]; then
        echo -e "\n" >> "${ZONEFILE}"
        cat "$DSSET_FILE" >> "${ZONEFILE}"
        ((DSSET_COUNT++))
    fi
done
echo "$DSSET_COUNT dssets added"

# Only use -o if origin is set through the domain variable 
if [ -n "$DOMAIN" ]; then
    sudo dnssec-signzone -o ${DOMAIN} -N INCREMENT -t -K . -S "$ZONEFILE"
else
    sudo dnssec-signzone -N INCREMENT -t -K . -S "$ZONEFILE"
fi

# remove .tmp and remove tmp zonefile
mv "${ZONEFILE}.signed" "${ZONEFILE%.tmp}.signed"
rm -f "$ZONEFILE"
