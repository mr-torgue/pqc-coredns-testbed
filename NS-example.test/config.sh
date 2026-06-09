DOMAIN="example.test."
TLS_DS="rsa:2048"
DNSSEC_DS="P256_FALCON512"
ZONEFILE="db.example.test"
./genkey.sh -f ${DOMAIN} -t ${TLS_DS} -d ${DNSSEC_DS}
./signzone.sh -z ${ZONEFILE}