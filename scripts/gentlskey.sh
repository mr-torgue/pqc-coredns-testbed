#!/bin/bash

usage() {
    echo "Usage: $0 -f/--fqdn [domainname] -t/--tls [TLS digital signature scheme] [-w/--wildcard]"
    exit 1
}

WILDCARD=false
FQDNS=()

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -f|--fqdn) FQDNS+=("$2"); shift ;;
        -t|--tls) TLS_DS="$2"; shift ;;
        -w|--wildcard) WILDCARD=true ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

if [[ ${#FQDNS[@]} -eq 0 ]]; then
    echo "Error: At least one FQDN is required"
    usage
fi

if [[ -z "$TLS_DS" ]]; then
    TLS_DS="rsa:4096"
    echo "Debug: Using default TLS digital signature scheme: $TLS_DS"
fi

for FQDN in "${FQDNS[@]}"; do
    if [[ "$WILDCARD" == true ]]; then
        SUBJECT_ALT_NAMES+="DNS:*.${FQDN},DNS:${FQDN},DNS:ns.${FQDN},DNS:ns1.${FQDN},"
    else
        SUBJECT_ALT_NAMES+="DNS:${FQDN},DNS:ns.${FQDN},DNS:ns1.${FQDN},"
    fi
    if [[ "$FQDN" == "." ]]; then
        SUBJECT_ALT_NAMES+="DNS:ns1.root,"
    fi
done
SUBJECT_ALT_NAMES=${SUBJECT_ALT_NAMES%,}

echo "Generating TLS certificates for FQDN: $FQDN"
echo "TLS digital signature scheme: $TLS_DS"
sudo openssl req -x509 -nodes -days 365 -newkey ${TLS_DS} -keyout key.pem -out cert.pem -subj "/CN=*.${FQDN}" -addext "subjectAltName=DNS:$SUBJECT_ALT_NAMES"