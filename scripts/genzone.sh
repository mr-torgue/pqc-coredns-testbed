#!/bin/bash

# Default values
LOCATION=""
ALGORITHM=""
NUM_RECORDS=0
WILDCARD=false

# Parse command line arguments
while getopts "l:a:n:wi:" opt; do
  case $opt in
    l) LOCATION=$OPTARG ;;
    a) ALGORITHM=$OPTARG ;;
    n) NUM_RECORDS=$OPTARG ;;
    w) WILDCARD=true ;;
    i) NS_IP=$OPTARG ;;
    \?) echo "Invalid option -$OPTARG" >&2; exit 1 ;;
  esac
done

# Check if required parameters are set
if [[ -z "$LOCATION" || -z "$ALGORITHM" || -z "$NS_IP" ]]; then
    echo "Usage: $0 -l [LOCATION] -a [ALGORITHM] -n [number of records] [-w] -i [IP_ADDRESS]"
    exit 1
fi

# Check if NUM_RECORDS exceeds 2000
if [ "$NUM_RECORDS" -gt 2000 ]; then
    echo "Error: Number of records cannot exceed 2000" >&2
    exit 1
fi

# Generate the Zone File Header
cat <<EOF
\$TTL    604800
@               IN              SOA             ns1.${LOCATION}.test. hostmaster.${LOCATION}.test. (
                                                                                            6    ; Serial
                                                                                            604800       ; Refresh
                                                                                            86400        ; Retry
                                                                                            2419200      ; Expire
                                                                                            604800 )     ; Negative Cache TTL
; name servers - NS records
@               IN              NS              ns1.${LOCATION}.test.
; name servers - A records
ns1.${LOCATION}.test.               IN              A               ${NS_IP}

; Burn-in A record
test.${ALGORITHM}-${LOCATION}.test.             IN              A               42.42.42.42
EOF

# Include Wildcard record if -w is set
if [ "$WILDCARD" = true ]; then
    echo "*.${ALGORITHM}-${LOCATION}.test.            IN              A               42.42.42.42"
fi

echo ""
echo "; Test A records"

# Generate the test records
for (( i=0; i<$NUM_RECORDS; i++ ))
do
    octet1=$((i / 256))
    octet2=$((i % 256))
    printf "test%d.%s-%s.test.            0            IN              A               42.42.%d.%d\n" \
    "$i" "$ALGORITHM" "$LOCATION" "$octet1" "$octet2"
done