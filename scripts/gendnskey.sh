#!/bin/bash

usage() {
    echo "Usage: $0 -f/--fqdn [domainname] -d/--dnssec [DNSSEC digital signature scheme]"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -f|--fqdn) FQDN="$2"; shift ;;
        -d|--dnssec) DNSSEC_DS="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

if [[ -z "$FQDN" ]]; then
    echo "Error: FQDN is required"
    usage
fi

if [[ -z "$DNSSEC_DS" ]]; then
    DNSSEC_DS="P256_FALCON512"
    echo "Debug: Using default DNSSEC digital signature scheme: $DNSSEC_DS"
fi

echo "Generating DNSSEC keys for FQDN: $FQDN"
echo "DNSSEC digital signature scheme: $DNSSEC_DS"
if [[ "$DNSSEC_DS" == "RSASHA256" ]]; then
    sudo dnssec-keygen -a ${DNSSEC_DS} -n ZONE -b 3072 ${FQDN}
    sudo dnssec-keygen -a ${DNSSEC_DS} -n ZONE -f KSK -b 3072 ${FQDN}
else
    sudo dnssec-keygen -a ${DNSSEC_DS} -n ZONE ${FQDN}
    sudo dnssec-keygen -a ${DNSSEC_DS} -n ZONE -f KSK ${FQDN}
fi
