: '
Name: experiment
Description: experiment starts by querying test.example.test and ignores the data to make sure the NS is loaded in cache.
After that it iterates over test0.example.test to test19.example.test and stores the RTT and corresponding timestamp.

Variables can be set trough the CLI.

It generates two files:
    1. [label]-[strategy]-[algorithm]-[timestamp].csv : contains the data in csv format
    2. [label]-[strategy]-[algorithm]-[timestamp].txt : contains the raw output from the kdig command

Example dig outcome:
;; Query time: 26 msec
;; SERVER: 127.0.0.53#53(127.0.0.53) (UDP)
;; WHEN: Fri Jan 09 12:08:41 AEDT 2026
;; MSG SIZE  rcvd: 55
'


#!/bin/bash

# Default values
RESOLVER=localhost
PORT=53
LABEL=""
DESCRIPTION=""
DOMAIN="test.example.test"
COUNT=20
RATE=0
DELAY=0
REPEAT=1
NR_PROCESSES=1
CLIENT="UDP"
CONFIGNAME=""
NODNSSEC=false

# Help function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -r, --resolver   DNS resolver IP or hostname (default: localhost)"
    echo "  -p, --port       Port number (default: 53)"
    echo "  -l, --label      Label for the filename (default: \"\")"
    echo "  -d, --description Description for the query (default: \"\")"
    echo "  -a, --algorithm  Algorithm that is used (required)"
    echo "  -s, --strategy   Strategy that is used (required)"
    echo "  -n, --processes  The number of processes (default: 1)"
    echo "  --domain         Domain to query (default: test.example.test)"
    echo "  --count          number of queries (default: 20)"
    echo "  --rate           Rate limit, docker only (default: 0)"
    echo "  --delay          Network delay, docker only (default: 0)"
    echo "  --repeat         The number of times this experiment is repeated (default: 1)"
    echo "  -c, --client     Client protocol (DoQ, DoT, UDP, or TCP, default: UDP)"
    echo "  -f, --config     Configuration name (default: \"\")"
    echo "  --nodnssec       Disable DNSSEC validation (default: false)"
    echo "  -h, --help       Show this help message"
    exit 1
}

# Parse command line options
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -r|--resolver) RESOLVER="$2"; shift ;;
        -p|--port) PORT="$2"; shift ;;
        -l|--label) LABEL="$2"; shift ;;
        -d|--description) DESCRIPTION="$2"; shift ;;
        -a|--algorithm) ALGORITHM="$2"; shift ;;
        -s|--strategy) STRATEGY="$2"; shift ;;
        -n|--processes) NR_PROCESSES="$2"; shift ;;
        --domain) DOMAIN="$2"; shift ;;
        --count) COUNT="$2"; shift ;;
        --rate) RATE="$2"; shift ;;
        --delay) DELAY="$2"; shift ;;
        --repeat) REPEAT="$2"; shift ;;
        -c|--client) CLIENT="$2"; shift ;;
        -f|--config) CONFIGNAME="$2"; shift ;;
        --nodnssec) NODNSSEC="true"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validate required parameters
if [[ -z "$RESOLVER" || -z "$ALGORITHM" || -z "$STRATEGY" || -z "$DOMAIN" ]]; then
    echo "Error: Missing required parameter(s)."
    usage
fi

# Validate client protocol
if [[ ! "$CLIENT" =~ ^(UDP|TCP|DoQ|DoT)$ ]]; then
    echo "Error: Invalid client protocol. Must be UDP, TCP, DoQ, or DoT."
    usage
fi

# Set kdigclient based on CLIENT protocol
kdigclient=""
case "$CLIENT" in
    TCP) kdigclient="+tcp" ;;
    DoT) kdigclient="+tls" ;;
    DoQ) kdigclient="+quic" ;;
    *) kdigclient="" ;;
esac

# Generate a random hex string
RANDOM_HEX=$(openssl rand -hex 4)

# Print configuration
echo "Configuration:"
echo "  Resolver:    $RESOLVER"
echo "  Port:        $PORT"
echo "  Label:       $LABEL"
echo "  Description: $DESCRIPTION"
echo "  Algorithm:   $ALGORITHM"
echo "  Strategy:    $STRATEGY"
echo "  Processes:   $NR_PROCESSES"
echo "  Domain:      $DOMAIN"
echo "  Count:       $COUNT"
echo "  Rate:        $RATE"
echo "  Delay:       $DELAY"
echo "  Repeat:      $REPEAT"
echo "  Client:      $CLIENT"
echo "  kdigclient:  $kdigclient"
echo "  Configname:  $CONFIGNAME"
echo "  DNSSEC disabled:  $NODNSSEC"
echo "  RANDOM_HEX:  $RANDOM_HEX"

read -p "do you want to run the experiment with these settings? (Y/N): " choice

# Check the user's input
if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    echo "Stopping..."
    exit 1
fi


TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
FILENAME="${LABEL}-${STRATEGY}-${ALGORITHM}-${TIMESTAMP}"
# Create directory name
DIR_NAME="${CONFIGNAME}-${LABEL}-$(date +%Y-%m-%d)-${RANDOM_HEX}"
# Create directory
mkdir -p "$DIR_NAME"
# Set file paths
CSV_FILE="${DIR_NAME}/${FILENAME}.csv"
JSON_FILE="${DIR_NAME}/${FILENAME}.json"
TXT_FILE="${DIR_NAME}/${FILENAME}.txt"


parse_dig_result() {
    local log_line="$1"
    local domain="$2"
    local query_time=""
    local timestamp=""
    local server=""
    local status=""
    local protocol=""

    # Extract query time (e.g., "26 msec")
    # dig: ;; Query time: 51 msec
    # kdig: ;; From 16.51.132.206@53(UDP) in 50.6 ms
    #if [[ "$log_line" =~ \;\;[[:space:]]Query[[:space:]]time:[[:space:]]([0-9]+)[[:space:]]msec ]]; then
    #    query_time="${BASH_REMATCH[1]}"
    #fi
    if [[ "$log_line" =~ \;\;[[:space:]]From[[:space:]]([^@]+@[0-9]+)\(([A-Za-z]+)\)[[:space:]]in[[:space:]]([0-9.]+)[[:space:]]ms ]]; then
        server="${BASH_REMATCH[1]}"
        protocol="${BASH_REMATCH[2]}"
        query_time="${BASH_REMATCH[3]}"
    fi

    # Extract timestamp (e.g., "Fri Jan 09 12:08:41 AEDT 2026")
    # dig: ;; WHEN: Tue Jun 16 12:09:35 AEST 2026
    # kdig: ;; Time 2026-06-16 12:13:56 AEST
    #if [[ "$log_line" =~ \;\;[[:space:]]WHEN:[[:space:]]([A-Za-z]{3}[[:space:]][A-Za-z]{3}[[:space:]][0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]][A-Za-z]{3,4}[[:space:]][0-9]{4}) ]]; then
    if [[ "$log_line" =~ \;\;[[:space:]]Time[[:space:]]([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]][A-Za-z]{3,4}) ]]; then
        timestamp="${BASH_REMATCH[1]}"
    fi

    # Extract server (e.g., "127.0.0.53#53")
    #if [[ "$log_line" =~ \;\;[[:space:]]SERVER:[[:space:]]([0-9\.]+#[0-9]+) ]]; then
    #    server="${BASH_REMATCH[1]}"
    #fi

    # Extract status (e.g., "NOERROR", "NXDOMAIN", "SERVFAIL")
    if [[ "$log_line" =~ \;\;[[:space:]]-\>\>HEADER\<\<-.*status:[[:space:]]([A-Z]+) ]]; then
        status="${BASH_REMATCH[1]}"
    fi

    # Extract UDP or TCP
    #if [[ "$log_line" =~ \;\;[[:space:]]SERVER:.*\(([A-Z]+)\) ]]; then
    #    protocol="${BASH_REMATCH[1]}"
    #fi

    # Print results
    printf "Timestamp: $timestamp\n" >> "$TXT_FILE"
    printf "Query Time: ${query_time}ms\n" >> "$TXT_FILE"
    printf "Server: $server\n" >> "$TXT_FILE"
    printf "Status: $status\n" >> "$TXT_FILE"
    # add to CSV
    printf "\"$domain\",\"$timestamp\",\"$server\",\"$status\",\"$query_time\"\n" >> "$CSV_FILE"
}

# Function to run a single dig query and process results
run_query() {
    local domain="$1"
    local output
    if [[ "$NODNSSEC" == "true" ]]; then
        output=$((time kdig @$RESOLVER -p $PORT +timeout=10 $kdigclient $domain) 2>&1)
    else
        output=$((time kdig @$RESOLVER -p $PORT +timeout=10 +dnssec $kdigclient $domain) 2>&1)
    fi
    printf "$output\n" >> "$TXT_FILE"
    parse_dig_result "$output" "$domain"
}

# write the info to file
jq -n \
    --arg label "$LABEL" \
    --arg description "$DESCRIPTION" \
    --arg algorithm "$ALGORITHM" \
    --arg strategy "$STRATEGY" \
    --arg delay "$DELAY" \
    --arg rate "$RATE" \
    --arg client "$CLIENT" \
    --arg configname "$CONFIGNAME" \
    '{label: $label, description: $description, algorithm: $algorithm, strategy: $strategy, delay: $delay, rate: $rate, client: $client, configname: $configname}' \
    >> "$JSON_FILE"
# write headers
printf "\"Domain\",\"Timestamp\",\"Resolver\",\"Status\",\"Query Time\"\n" >> "$CSV_FILE"

# Run initial query
run_query "$DOMAIN"

# Run concurrent queries
for ((r = 0; r < REPEAT; r++)); do
    # Create an array to hold PIDs
    pids=()

    for ((i = 0; i < COUNT; i++)); do 
        prefix="${DOMAIN%%.*}${i}"
        newdomain=$(echo "$prefix.${DOMAIN#*.}")

        # Run query in background and store PID
        run_query "$newdomain" &
        pids+=($!)

        # Limit number of concurrent processes
        if (( ${#pids[@]} >= NR_PROCESSES )); then
            wait -n
            pids=("${pids[@]:1}")
        fi
    done

    # Wait for all background processes to complete
    wait
done
