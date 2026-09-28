#! /bin/bash
: '
starts monitoring for a given configuration/experiment.
'

PCAP_FILE="false"
INTERVAL=0
LABEL="default"
REDIRECT_OUTPUT="false"
while getopts ":c:pi:l:o" opt; do
  case $opt in
    c)
      CONFIG_DIR="$OPTARG"
      ;;
    p)
      PCAP_FILE="true"
      ;;
    i)
      INTERVAL="$OPTARG"
      ;;
    l)
      LABEL="$OPTARG"
      ;;
    o)
      REDIRECT_OUTPUT="true"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

if [ -z "$CONFIG_DIR" ]; then
    echo "Error: Please provide a directory name with -c option."
    exit 1
fi

# check if config is running

echo -e "---------------------------"
read -p "do you want to run bind with these settings? (Y/N): " choice

# Check the user's input
if [[ "$choice" =~ ^[Yy]$ ]]; then
    cd "$CONFIG_DIR"
    if [ -n "$LABEL" ]; then
        exp_folder="experiment_${LABEL}_$(date +%Y%m%d_%H%M%S)"
    else
        exp_folder="experiment_$(date +%Y%m%d_%H%M%S)"
    fi
    mkdir -p "$exp_folder"
    echo "Created run folder: $CONFIG_DIR/$exp_folder"

    pkill sar
    pkill coredns
    pkill tcpdump

    # start monitoring
    if [ "$INTERVAL" -ne 0 ]; then
        echo "Start CPU, Network, and Memory monitoring using sar with interval $INTERVAL"
        current_date=$(date +%d-%m-%y)
        echo "Start time: $(date)" > cpu-$current_date.log
        echo "Start time: $(date)" > mem-$current_date.log
        echo "Start time: $(date)" > net-$current_date.log
        (sar -u $INTERVAL >> $exp_folder/cpu-$current_date.log &); (sar -n DEV $INTERVAL --iface=ens5 >> $exp_folder/net-$current_date.log &); (sar -r $INTERVAL >> $exp_folder/mem-$current_date.log &)
    else
        echo "Monitoring disabled (interval set to 0)"
    fi

    if [ "$PCAP_FILE" = "true" ]; then
        echo "PCAP will be stored in $exp_folder/$LABEL"
        tcpdump -i any '(port 53 or port 853 or port 8853) and (udp or tcp)' -w "$exp_folder/$LABEL" &
    fi
else
    echo "aborting..."
    exit 1
fi