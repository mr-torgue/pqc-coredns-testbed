#! /bin/bash
: '
starts monitoring for a given configuration.
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

# print $CONFIG_DIR/config.json
echo -e "-------------------------------------"
echo -e "|          config.json              |"
echo -e "-------------------------------------"
if [ -f "$CONFIG_DIR/config.json" ]; then
    echo -e "\nContents of $CONFIG_DIR/config.json:"
    cat "$CONFIG_DIR/config.json"
else 
    echo "config.json not found!"
    exit
fi

# print $CONFIG_DIR/CoreFile
echo -e "-------------------------------------"
echo -e "|          Core File                |"
echo -e "-------------------------------------"
if [ -f "$CONFIG_DIR/CoreFile" ]; then
    echo -e "\nContents of $CONFIG_DIR/CoreFile:"
    cat "$CONFIG_DIR/CoreFile"
else 
    echo "CoreFile not found!"
    exit
fi

#dir=$(jq -r '."Config Directory"' /opt/coredns/config.json)
echo -e "-------------------------------------"
echo -e "|          Available Keys           |"
echo -e "-------------------------------------"
while read -r file; do
    FILE_ALG=$(sed -n '2p' "$file" | awk -F'[()]' '{print $2}') 
    # check if key file exists
    key_file="${file%.private}.key"
    if [ ! -f "$key_file" ]; then
        echo "Error: Cannot find '$key_file'"
        exit 1
    fi
    # read keyfile
    first_line=$(sed -n '1p' "$key_file")
    if [[ "$first_line" == *"This is a key-signing key"* ]]; then
        echo "KSK Algorithm: $FILE_ALG"
    elif [[ "$first_line" == *"This is a zone-signing key"* ]]; then
        echo "ZSK Algorithm: $FILE_ALG"
    else
        echo "Error: '$key_file' is neither a KSK or ZSK"
        exit 1
    fi
done < <(find "$CONFIG_DIR" -type f -name "K*.private")
echo -e "---------------------------"
read -p "do you want to run bind with these settings? (Y/N): " choice

# Check the user's input
if [[ "$choice" =~ ^[Yy]$ ]]; then
    cd "$CONFIG_DIR"
    if [ -n "$LABEL" ]; then
        run_folder="run_${LABEL}_$(date +%Y%m%d_%H%M%S)"
    else
        run_folder="run_$(date +%Y%m%d_%H%M%S)"
    fi
    mkdir -p "$run_folder"
    echo "Created run folder: $CONFIG_DIR/$run_folder"

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
        (sar -u $INTERVAL >> $run_folder/cpu-$current_date.log &); (sar -n DEV $INTERVAL --iface=ens5 >> $run_folder/net-$current_date.log &); (sar -r $INTERVAL >> $run_folder/mem-$current_date.log &)
    else
        echo "Monitoring disabled (interval set to 0)"
    fi

    if [ "$PCAP_FILE" = "true" ]; then
        echo "PCAP will be stored in $run_folder/$LABEL"
        tcpdump -i any '(port 53 or port 853 or port 8853) and (udp or tcp)' -w "$run_folder/$LABEL" &
    fi

    if [ "$DEBUG" = "true" ]; then
        echo "DEBUG MODE"
        gdb --batch -ex "run" -ex "bt" -ex "quit" --args /opt/coredns/coredns -conf CoreFile
    else
        if [ "$REDIRECT_OUTPUT" = "true" ]; then
            /opt/coredns/coredns -conf CoreFile > "$run_folder/coredns.txt" 2>&1
        else
            /opt/coredns/coredns -conf CoreFile
        fi
    fi
else
    echo "aborting..."
    exit 1
fi