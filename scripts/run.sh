#! /bin/bash
: '
runs coredns and displays debug information
'

DEBUG="false"
LABEL="default"
while getopts ":c:dl:" opt; do
  case $opt in
    c)
      CONFIG_DIR="$OPTARG"
      ;;
    d)
      DEBUG="true"
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

echo "CONFIG_DIR: $CONFIG_DIR"
echo "DEBUG: $DEBUG"
echo "LABEL: $LABEL"

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
    FILE_ALG=$(sudo sed -n '2p' "$file" | awk -F'[()]' '{print $2}') 
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
    pkill coredns

    if [ "$DEBUG" = "true" ]; then
        echo "DEBUG MODE"
        sudo gdb --batch -ex "run" -ex "bt" -ex "quit" --args /opt/coredns/coredns -conf CoreFile
    else
        if [ -f "coredns.service" ]; then
            sudo cp "coredns.service" /etc/systemd/system/coredns.service
            sudo systemctl daemon-reload
            sudo systemctl enable coredns
            sudo systemctl start coredns
        else
            echo "Could not find service file, starting as normal process."
            sudo /opt/coredns/coredns -conf CoreFile
        fi

    fi
else
    echo "aborting..."
    exit 1
fi