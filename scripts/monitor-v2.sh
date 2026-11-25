#!/usr/bin/env bash
#
# WARNING: AI Generated!
# should be okay because the last script worked, but there might be some weird stuff. 
#
# Monitoring harness for a running coredns experiment.
#
# Usage: monitor.sh -c CONFIG_DIR [-p] [-i N] [-l LABEL]
#   -c DIR   config directory coredns was started with (required)
#   -p       also capture a PCAP of DNS traffic (needs sudo)
#   -i N     sample CPU/memory/network every N seconds (sar)
#   -l LABEL name for the experiment folder
#
# Creates CONFIG_DIR/experiment_<label>_<timestamp>/ with:
#   coredns.txt             queries logged after the start of the run
#   cpu/mem/net-<date>.log  sar samples (-i)
#   capture_<label>.pcap    DNS packets on port 53/853/8853 (-p)
#   monitor.log             what was started, and when
# Runs until Ctrl+C / SIGTERM; capture jobs are stopped gently so the
# PCAP footer and the final sar samples are written.

set -u

PCAP=false INTERVAL=0 LABEL=default CONFIG_DIR=""

while getopts ":c:pi:l:" opt; do
    case $opt in
        c) CONFIG_DIR=$OPTARG ;;
        p) PCAP=true ;;
        i) [[ $OPTARG =~ ^[1-9][0-9]*$ ]] || { echo "Error: -i needs a positive integer." >&2; exit 1; }
           INTERVAL=$OPTARG ;;
        l) LABEL=$OPTARG ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
        :)  echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
    esac
done

[ -d "$CONFIG_DIR" ] || { echo "Usage: $0 -c CONFIG_DIR [-p] [-i N] [-l LABEL]" >&2; exit 1; }

# only run against the coredns using this config directory
pgrep -x coredns >/dev/null || { echo "Error: coredns is not running." >&2; exit 1; }
ps -C coredns -o args= | grep -Fq -- "$CONFIG_DIR" ||
    { echo "Error: coredns is not using configuration directory: $CONFIG_DIR" >&2; exit 1; }

echo "CONFIG_DIR: $CONFIG_DIR"
echo "PCAP:       $PCAP"
echo "INTERVAL:   $INTERVAL"
echo "LABEL:      $LABEL"
read -rp "Start monitoring with these settings? (y/N) " ans
[[ $ans =~ ^[Yy]$ ]] || { echo "Aborting."; exit 1; }

# experiment folder
EXP_DIR="$CONFIG_DIR/experiment_${LABEL}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EXP_DIR" || exit 1
cd "$EXP_DIR" || exit 1
echo "Experiment folder: $PWD"
LOG=monitor.log
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# ---------- cleanup: stop capture jobs gently, then hard-kill survivors ----------
PIDS=()
cleanup() {
    trap - EXIT INT TERM
    [ ${#PIDS[@]} -eq 0 ] || kill -INT "${PIDS[@]}" 2>/dev/null   # lets tcpdump write the PCAP footer
    sleep 1
    [ ${#PIDS[@]} -eq 0 ] || kill -KILL "${PIDS[@]}" 2>/dev/null
    wait 2>/dev/null
    echo "Done. Results in $PWD"
}
trap 'echo; cleanup' EXIT INT TERM

# ---------- follow the query log (only queries from now on) ----------
COREDNS_LOG=/var/log/coredns.log
if [ -f "$COREDNS_LOG" ]; then
    tail -c +$(( $(stat -c %s "$COREDNS_LOG") + 1 )) -F "$COREDNS_LOG" > coredns.txt & PIDS+=($!)
    log "following $COREDNS_LOG -> coredns.txt"
else
    echo "Warning: $COREDNS_LOG not found; query capture disabled." >&2
fi

# ---------- sar resource sampling ----------
if [ "$INTERVAL" -gt 0 ]; then
    IFACE=${IFACE:-ens5}   # override with IFACE=eth0 monitor.sh ...
    ts=$(date +%d-%m-%y)
    sar -u "$INTERVAL"              > "cpu-$ts.log" 2>&1 & PIDS+=($!)
    sar -r "$INTERVAL"              > "mem-$ts.log" 2>&1 & PIDS+=($!)
    sar -n DEV "$INTERVAL" --iface "$IFACE" > "net-$ts.log" 2>&1 & PIDS+=($!)
    log "sar started (interval ${INTERVAL}s, iface $IFACE)"
    # Per-process stats instead of system-wide sar:
    #   <path>/monitor.sh coredns -r -i "$INTERVAL" > proc-$ts.log 2>&1 & PIDS+=($!)
else
    echo "Resource sampling disabled (-i not given)."
fi

# ---------- optional pcap of DNS traffic ----------
if [ "$PCAP" = true ]; then
    sudo tcpdump -i any -U -s 0 '(port 53 or port 853 or port 8853) and (udp or tcp)' \
        -w "capture_${LABEL}.pcap" > tcpdump.log 2>&1 & PIDS+=($!)
    log "tcpdump started -> capture_${LABEL}.pcap"
fi

echo "Monitoring... press Ctrl+C to stop."

# The poll loop (not `wait`) matters here: bash delays trapped signals
# while blocked in wait, so SIGINT/SIGTERM would only be handled after
# every capture job exits by itself. With sleep 1 the trap runs within a second.
while kill -0 "${PIDS[@]}" 2>/dev/null; do
    sleep 1
done
