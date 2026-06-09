#!/bin/bash

usage() {
    echo "Usage: $0 -z/--zonefile <filename> [-d/--ds <filename>] [-f/--fqdn <domain>]"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -z|--zonefile) ZONEFILE="$2"; shift ;;
        -d|--ds) DSFILE="$2"; shift ;;
        -f|--fqdn) DOMAIN="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

if [ -z "$ZONEFILE" ]; then
    echo "Error: Zone file is required."
    usage
fi

if [ -n "$DSFILE" ]; then
    if [ ! -f "$DSFILE" ]; then
        echo "Error: DS file does not exist."
        exit 1
    fi
    cp "$ZONEFILE" "${ZONEFILE}.tmp"
    cat "$DSFILE" >> "${ZONEFILE}.tmp"
    ZONEFILE="${ZONEFILE}.tmp"
fi

# Only use -o if origin is set through the domain variable 
if [ -n "$DOMAIN" ]; then
    sudo dnssec-signzone -o ${DOMAIN} -N INCREMENT -t -K . -S "$ZONEFILE"
else
    sudo dnssec-signzone -N INCREMENT -t -K . -S "$ZONEFILE"
fi

if [ -n "$DSFILE" ]; then
    rm -f "$ZONEFILE"
fi
