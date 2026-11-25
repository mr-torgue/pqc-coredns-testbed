#!/usr/bin/env bash
# WARNING: AI generated!
# Should work, but not tested thoroughly.
#
# Per-process CPU / memory / network monitor for a running experiment.
#
# Usage: monitor.sh [-r] [-i N] [-n N] [-c DIR] [-p] [-l LABEL] [name|pid|path]

set -u

INTERVAL=1 COUNT=0 RECURSE=false TARGET=""
CONFIG_DIR="" PCAP=false LABEL=default

while [ $# -gt 0 ]; do
    case $1 in
        -r) RECURSE=true ;;
        -i) [ $# -ge 2 ] || { echo "Error: -i needs an argument." >&2; exit 1; }
            INTERVAL=$2; shift ;;
        -n) [ $# -ge 2 ] || { echo "Error: -n needs an argument." >&2; exit 1; }
            COUNT=$2; shift ;;
        -c) [ $# -ge 2 ] || { echo "Error: -c needs an argument." >&2; exit 1; }
            CONFIG_DIR=$2; shift ;;
        -l) [ $# -ge 2 ] || { echo "Error: -l needs an argument." >&2; exit 1; }
            LABEL=$2; shift ;;
        -p) PCAP=true ;;
        -h) echo "Usage: $0 [-r] [-i N] [-n N] [-c DIR] [-p] [-l LABEL] [name|pid|path]"
            exit 0 ;;
        -*) echo "Error: unknown option: $1" >&2; exit 1 ;;
        *)  TARGET=$1 ;;
    esac
    shift
done

[[ $INTERVAL =~ ^[1-9][0-9]*$ ]] || { echo "Error: interval must be a positive integer." >&2; exit 1; }
[[ $COUNT =~ ^[0-9]+$ ]] || { echo "Error: count must be a non-negative integer." >&2; exit 1; }
[ -n "$TARGET" ] || TARGET=coredns
[ -z "$CONFIG_DIR" ] || [ -d "$CONFIG_DIR" ] || { echo "Error: -c needs an existing directory." >&2; exit 1; }
[ "$PCAP" = false ] || [ -n "$CONFIG_DIR" ] || { echo "Error: -p requires -c DIR." >&2; exit 1; }

HZ=$(getconf CLK_TCK 2>/dev/null) || HZ=100
BASE=${TARGET##*/}

proc_table() {
    awk '
    {
        t = $0; i = 0
        while ((j = index(t, ") ")) > 0) {
            i += j; t = substr(t, j + 2)
        }
        split(t, f, " ")
        if (f[1] == "Z") next
        pid = $0; sub(/\(.*/, "", pid); gsub(/[ ]/, "", pid)
        n = index($0, "(")
        print pid, f[2], f[12] + f[13], substr($0, n + 1, i - n - 1)
    }' /proc/[0-9]*/stat 2>/dev/null
}

cmdline_matches() {
    local pid="$1"
    [ -r "/proc/$pid/cmdline" ] || return 1
    local arg0
    arg0=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | head -n 1)
    [ -n "$arg0" ] || return 1
    [ "$arg0" = "$TARGET" ] || [ "${arg0##*/}" = "$BASE" ]
}

find_roots() {
    if [[ $TARGET =~ ^[0-9]+$ ]]; then
        awk -v t="$TARGET" '$1 == t {print $1}' <<< "$TABLE"
    else
        local matched
        matched=$(awk -v t="$TARGET" -v b="$BASE" '$4 == t || $4 == b {print $1}' <<< "$TABLE")
        if [ -n "$matched" ]; then
            printf '%s\n' "$matched"
        else
            awk '{print $1}' <<< "$TABLE" | while read -r p; do
                cmdline_matches "$p" && echo "$p"
            done
        fi
    fi
}

expand() {
    local all="$1" last="$1" kids
    while :; do
        kids=$(awk -v p="$last" -v k="$all" '
            BEGIN { split(p, a, " "); for (i in a) par[a[i]] = 1
                    split(k, a, " "); for (i in a) known[a[i]] = 1 }
            par[$2] && !($1 in known) { print $1 }' <<< "$TABLE")
        [ -n "$kids" ] || break
        all="$all $kids"; last="$kids"
    done
    echo "$all"
}

cpu_ticks() {
    awk -v k="$1" 'BEGIN { n = split(k, a, " "); for (i = 1; i <= n; i++) w[a[i]] = 1 }
        { t += $3 * ($1 in w) } END { print t + 0 }' <<< "$TABLE"
}

rss_kb() {
    local p v t=0
    for p in $1; do
        v=$(awk '/^VmRSS:/{print $2}' "/proc/$p/status" 2>/dev/null)
        t=$(( t + ${v:-0} ))
    done
    echo $t
}

net_bytes() {
    local first_pid="${1%% *}"
    awk 'NR > 2 && $1 != "lo:" { rx += $2; tx += $10 } END { print rx + 0, tx + 0 }' \
        "/proc/$first_pid/net/dev" 2>/dev/null || echo 0 0
}

collect_target_pids() {
    local pids
    pids=$(find_roots)
    [ -n "$pids" ] || { echo ""; return; }
    [ "$RECURSE" = true ] && pids="$(expand "$pids")"
    echo "$pids"
}

TABLE=$(proc_table)
PIDS=$(collect_target_pids)
[ -n "$PIDS" ] || { echo "Error: no process matches '$TARGET'." >&2; exit 1; }

if [ -n "$CONFIG_DIR" ]; then
    ok=""
    for p in $PIDS; do
        if tr "\0" " " < "/proc/$p/cmdline" 2>/dev/null | grep -Fq -- "$CONFIG_DIR"; then
            ok=1; break
        fi
    done
    [ -n "$ok" ] || { echo "Error: '$TARGET' is not using configuration directory: $CONFIG_DIR" >&2; exit 1; }
fi

prev_cpu=$(cpu_ticks "$PIDS")
read -r prev_rx prev_tx <<< "$(net_bytes "$PIDS")"

echo "Monitoring '$TARGET' every ${INTERVAL}s$([ "$RECURSE" = true ] && echo ', incl. sub-processes'); Ctrl+C to stop."
printf "%-8s %6s %10s %12s %12s\n" TIME CPU% RSS "RX/s" "TX/s"

BGPIDS=()
if [ -n "$CONFIG_DIR" ]; then
    echo "CONFIG_DIR: $CONFIG_DIR"
    echo "PCAP:       $PCAP"
    echo "LABEL:      $LABEL"
    read -rp "Start monitoring with these settings? (y/N) " ans
    [[ $ans =~ ^[Yy]$ ]] || { echo "Aborting."; exit 1; }

    EXP_DIR="$CONFIG_DIR/experiment_${LABEL}_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$EXP_DIR" || exit 1
    cd "$EXP_DIR" || exit 1
    echo "Experiment folder: $PWD"

    OUT="$PWD/proc.log"
    printf "%-8s %6s %10s %12s %12s\n" TIME CPU% RSS "RX/s" "TX/s" >> "$OUT"

    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> monitor.log; }
    log "monitoring target '$TARGET' (interval ${INTERVAL}s$([ "$RECURSE" = true ] && echo ", sub-processes included"))"

    cleanup() {
        trap - EXIT INT TERM
        if [ "${#BGPIDS[@]}" -gt 0 ]; then
            for p in "${BGPIDS[@]}"; do
                # Signal child processes (e.g., tcpdump under sudo) as well as the wrapper PID
                pkill -INT -P "$p" 2>/dev/null || true
                kill -INT "$p" 2>/dev/null || true
            done
            sleep 1
            for p in "${BGPIDS[@]}"; do
                pkill -KILL -P "$p" 2>/dev/null || true
                kill -KILL "$p" 2>/dev/null || true
                wait "$p" 2>/dev/null || true
            done
        fi
        echo "Done. Results in $PWD"
    }
    trap 'echo; cleanup' EXIT INT TERM

    COREDNS_LOG=/var/log/coredns.log
    if [ -f "$COREDNS_LOG" ]; then
        tail -c +$(( $(stat -c %s "$COREDNS_LOG") + 1 )) -F "$COREDNS_LOG" > coredns.txt & BGPIDS+=($!)
        log "following $COREDNS_LOG -> coredns.txt"
    else
        echo "Warning: $COREDNS_LOG not found; query capture disabled." >&2
    fi

    if [ "$PCAP" = true ]; then
        if [ "$(id -u)" -eq 0 ]; then
            tcpdump -i any -U -s 0 '(port 53 or port 853 or port 8853) and (udp or tcp)' \
                -w "capture_${LABEL}.pcap" > tcpdump.log 2>&1 & BGPIDS+=($!)
        else
            sudo tcpdump -i any -U -s 0 '(port 53 or port 853 or port 8853) and (udp or tcp)' \
                -w "capture_${LABEL}.pcap" > tcpdump.log 2>&1 & BGPIDS+=($!)
        fi
        log "tcpdump started -> capture_${LABEL}.pcap"
    fi
fi

n=0
while [ "$COUNT" -eq 0 ] || [ "$n" -lt "$COUNT" ]; do
    k=$INTERVAL
    while [ "$k" -gt 0 ]; do sleep 1; k=$((k - 1)); done

    TABLE=$(proc_table)
    PIDS=$(collect_target_pids)
    if [ -z "$PIDS" ]; then
        [ -n "$CONFIG_DIR" ] || echo "$(date +%T)  process ended."
        exit 0
    fi

    cpu=$(cpu_ticks "$PIDS")
    mem=$(rss_kb "$PIDS")
    read -r rx tx <<< "$(net_bytes "$PIDS")"

    line=$(awk -v t="$(date +%T)" -v dc=$((cpu - prev_cpu)) -v hz="$HZ" -v s="$INTERVAL" \
        -v m="$mem" -v rx=$((rx - prev_rx)) -v tx=$((tx - prev_tx)) \
        'BEGIN { printf "%-8s %5.1f%% %8.1fMB %8.0fkB/s %8.0fkB/s",
                 t, dc * 100 / (hz * s), m / 1024, rx / s / 1024, tx / s / 1024 }')

    if [ -n "$CONFIG_DIR" ]; then
        echo "$line" >> "$OUT"
    else
        echo "$line"
    fi

    prev_cpu=$cpu prev_rx=$rx prev_tx=$tx
    n=$((n + 1))
done
