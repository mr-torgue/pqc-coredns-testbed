#! /bin/bash
: '
runs coredns and displays debug information
'


DEBUG="false"
PCAP_FILE=""
while getopts ":c:d:p:" opt; do
  case $opt in
    d)
      DEBUG="true"
      ;;
    p)
      PCAP_FILE="$OPTARG"
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

echo "CONFIG_DIR: $CONFIG_DIR"
echo "DEBUG: $DEBUG"
echo "PCAP_FILE: $PCAP_FILE"


# Print OpenSSL version
echo "OpenSSL version:"
openssl version

# Print active OpenSSL providers
echo -e "\nActive OpenSSL providers:"
openssl list -providers

# Print Go version
echo -e "\nGo version:"
go version

# print information before running
echo "named version: $(named -v)"

if command -v sudo >/dev/null 2>&1; then
    echo "named version: $(sudo named -v)"
else
    echo "named version: $(named -v)"
fi

# Print CoreDNS version
echo -e "\nCoreDNS version:"
if [ -x /opt/coredns/coredns ]; then
    /opt/coredns/coredns --version
else
    echo "CoreDNS not found at /opt/coredns/coredns"
fi

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
cd $CONFIG_DIR
if [[ "$choice" =~ ^[Yy]$ ]]; then
    pkill coredns
    pkill tcpdump
    if [ -n "$PCAP_FILE" ]; then
        echo "PCAP file specified: $PCAP_FILE"
        tcpdump -i any '(port 53 or port 853 or port 8853) and (udp or tcp)' -w "$PCAP_FILE" &
    fi

    if [ "$DEBUG" = "true" ]; then
        echo "DEBUG MODE"
        gdb --batch -ex "run" -ex "bt" -ex "quit" --args /opt/coredns/coredns -conf CoreFile
    else
        /opt/coredns/coredns -conf CoreFile
    fi
else
    echo "aborting..."
    exit 1
fi