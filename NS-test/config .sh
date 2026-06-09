DSSET="dsset-.example.test"
DOMAIN="test."
TLS_DS="rsa:2048"
DNSSEC_DS="P256_FALCON512"
ZONEFILE="db.test"
./genkey.sh -f ${DOMAIN} -t ${TLS_DS} -d ${DNSSEC_DS}
./signzone.sh -z ${ZONEFILE} -f ${DOMAIN} -d ${DSSET}