#! /bin/bash
: '
Starts monitoring for a given configuration/experiment.
1. Collects PCAP if -p is given
2. Collects CPU/Mem/Net info with sar if -i [n] is provided with n > 0
3. Stores queries in coredns.txt
Creates a dedicated experiment folder under the given config directory.
'

PCAP_FILE="false"
INTERVAL=0
LABEL="default"
while getopts ":c:pi:l:" opt; do
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
if ! pgrep -f "coredns" > /dev/null; then
    echo "Error: coredns process is not running."
    exit 1
fi

if ! grep -q "$CONFIG_DIR" <<< "$(ps aux | grep coredns)"; then
    echo "Error: coredns is not using the specified configuration directory: $CONFIG_DIR"
    exit 1
fi


echo "CONFIG_DIR: $CONFIG_DIR"
echo "PCAP_FILE: $PCAP_FILE"
echo "INTERVAL: $INTERVAL"
echo "LABEL: $LABEL"
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
    echo "Created experiment folder: $CONFIG_DIR/$exp_folder"

    pkill sar
    pkill tcpdump

    # make sure all entries are logged for this experiment
    tail -n +1 -F /var/log/coredns.log >> $exp_folder/coredns.txt

    # start monitoring
    if [ "$INTERVAL" -ne 0 ]; then
        echo "Start CPU, Network, and Memory monitoring using sar with interval $INTERVAL"
        current_date=$(date +%d-%m-%y)
        echo "Start time: $(date)" > cpu-$current_date.log
        echo "Start time: $(date)" > mem-$current_date.log
        echo "Start time: $(date)" > net-$current_date.log
        (sudo sar -u $INTERVAL >> $exp_folder/cpu-$current_date.log &); (sudo sar -n DEV $INTERVAL --iface=ens5 >> $exp_folder/net-$current_date.log &); ( sudo sar -r $INTERVAL >> $exp_folder/mem-$current_date.log &)
    else
        echo "Monitoring disabled (interval set to 0)"
    fi

    if [ "$PCAP_FILE" = "true" ]; then
        echo "PCAP will be stored in $exp_folder/$LABEL"
        sudo tcpdump -i any '(port 53 or port 853 or port 8853) and (udp or tcp)' -w "$exp_folder/$LABEL" &
    fi
else
    echo "aborting..."
    exit 1
fi