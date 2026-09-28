#!/usr/bin/env bash

# Starts monitoring for a given configuration/experiment.
# 1. Collects PCAP if -p is given
# 2. Collects CPU/Mem/Net info with sar if -i [n] is given (n > 0)
# 3. Stores queries in coredns.txt
# Creates a dedicated experiment folder under the given config directory.
# Runs until CTRL+C / SIGTERM.
# Warning AI generated based on the old script

set -u

PCAP_FILE="false"
INTERVAL=0
LABEL="default"
CONFIG_DIR=""

usage() { echo "Usage: $0 -c CONFIG_DIR [-p] [-i N] [-l LABEL]"; exit 1; }

while getopts ":c:pi:l:" opt; do
  case $opt in
    c) CONFIG_DIR="$OPTARG" ;;
    p) PCAP_FILE="true" ;;
    i)
      if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -eq 0 ]; then
        echo "Error: -i requires a positive integer." >&2; exit 1
      fi
      INTERVAL="$OPTARG" ;;
    l) LABEL="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
  esac
done

[ -z "$CONFIG_DIR" ] && usage

# check if config is running
if ! pgrep -x coredns >/dev/null; then
    echo "Error: coredns process is not running." >&2
    exit 1
fi
if ! ps aux | grep '[c]oredns' | grep -q "$CONFIG_DIR"; then
    echo "Error: coredns is not using the specified configuration directory: $CONFIG_DIR" >&2
    exit 1
fi

echo "CONFIG_DIR: $CONFIG_DIR"
echo "PCAP_FILE:  $PCAP_FILE"
echo "INTERVAL:   $INTERVAL"
echo "LABEL:      $LABEL"
echo -e "---------------------------"
read -rp "Do you want to start monitoring with these settings? (y/N): " choice
[[ "$choice" =~ ^[Yy]$ ]] || { echo "Aborting..."; exit 1; }

cd "$CONFIG_DIR" || exit 1
EXP_FOLDER="experiment_${LABEL}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EXP_FOLDER"
echo "Created experiment folder: $PWD/$EXP_FOLDER"

# ---------- cleanup machinery ----------
PIDS=()

cleanup() {
    echo ""
    echo "Stopping monitoring..."
    # disable the trap so CTRL+C during cleanup doesn't re-enter
    trap - EXIT INT TERM
    # kill tcpdump gently first so the PCAP footer gets written
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -INT "$pid" 2>/dev/null || kill "$pid" 2>/dev/null
        fi
    done
    # give processes a moment to flush (pcap files, sar samples)
    sleep 1
    for pid in "${PIDS[@]}"; do
        kill -9 "$pid" 2>/dev/null
    done
    wait 2>/dev/null
    echo "Done. Results in $PWD/$EXP_FOLDER"
}
# makes sure that CTRL+C and others go to cleanup function
trap cleanup EXIT INT TERM

start_job() {  # start_job <logfile header> <command...>
    "$@" >>"$LOG" 2>&1 &
    PIDS+=($!)
}

LOG="$EXP_FOLDER/monitor.log"
start_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG"; }

# ---------- 3. follow the query log ----------
# Note the current size so we only capture queries that arrive from now on.
COREDNS_LOG=/var/log/coredns.log
if [ -f "$COREDNS_LOG" ]; then
    START_OFFSET=$(stat -c %s "$COREDNS_LOG")
    tail -c "+$((START_OFFSET + 1))" -F "$COREDNS_LOG" > "$EXP_FOLDER/coredns.txt" &
    PIDS+=($!)
    start_log "Following $COREDNS_LOG -> $EXP_FOLDER/coredns.txt"
else
    echo "Warning: $COREDNS_LOG not found; query capture disabled." >&2
fi

# ---------- 2. sar monitoring ----------
if [ "$INTERVAL" -ne 0 ]; then
    echo "Start CPU, Network, and Memory monitoring using sar with interval $INTERVAL"
    IFACE="${IFACE:-ens5}"   # override with IFACE=eth0 ./monitor.sh ...
    for what in cpu mem; do
        case $what in
            cpu) SAR_ARGS=(-u) ;;
            mem) SAR_ARGS=(-r) ;;
        esac
        sar "${SAR_ARGS[@]}" "$INTERVAL" > "$EXP_FOLDER/${what}-$(date +%d-%m-%y).log" 2>&1 &
        PIDS+=($!)
    done
    sar -n DEV "$INTERVAL" --iface="$IFACE" > "$EXP_FOLDER/net-$(date +%d-%m-%y).log" 2>&1 &
    PIDS+=($!)
    start_log "sar started (interval ${INTERVAL}s, iface $IFACE)"
else
    echo "Monitoring disabled (interval set to 0)"
fi

# ---------- 1. pcap ----------
if [ "$PCAP_FILE" = "true" ]; then
    PCAP="$EXP_FOLDER/capture_${LABEL}.pcap"
    echo "PCAP will be stored in $PCAP"
    tcpdump -i any -U -s 0 '(port 53 or port 853 or port 8853) and (udp or tcp)' -w "$PCAP" \
        >"$EXP_FOLDER/tcpdump.log" 2>&1 &
    PIDS+=($!)
    start_log "tcpdump started -> $PCAP"
fi

echo -e "\nMonitoring... press CTRL+C to stop.\n"

# ---------- keep running until CTRL+C ----------
while kill -0 "${PIDS[@]}" 2>/dev/null; do
    sleep 1
done