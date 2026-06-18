#!/bin/bash

usage() {
    echo "Usage: $0 -f/--fqdn [domainname] -t/--tls [TLS digital signature scheme] -d/--dnssec [DNSSEC digital signature scheme]"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -f|--fqdn) FQDN="$2"; shift ;;
        -t|--tls) TLS_DS="$2"; shift ;;
        -d|--dnssec) DNSSEC_DS="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

if [[ -z "$FQDN" ]]; then
    echo "Error: FQDN is required"
    usage
fi

if [[ -z "$TLS_DS" ]]; then
    TLS_DS="rsa:4096"
    echo "Debug: Using default TLS digital signature scheme: $TLS_DS"
fi

if [[ -z "$DNSSEC_DS" ]]; then
    DNSSEC_DS="P256_FALCON512"
    echo "Debug: Using default DNSSEC digital signature scheme: $DNSSEC_DS"
fi

echo "Generating TLS certificates for FQDN: $FQDN"
echo "TLS digital signature scheme: $TLS_DS"
sudo openssl req -x509 -nodes -days 365 -newkey ${TLS_DS} -keyout key.pem -out cert.pem -subj "/CN=${FQDN}" -addext "subjectAltName=DNS:${FQDN}"

echo "Generating DNSSEC keys for FQDN: $FQDN"
echo "DNSSEC digital signature scheme: $DNSSEC_DS"
sudo dnssec-keygen -a ${DNSSEC_DS} -n ZONE ${FQDN}
sudo dnssec-keygen -a ${DNSSEC_DS} -n ZONE -f KSK ${FQDN}
