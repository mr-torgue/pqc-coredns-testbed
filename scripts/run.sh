#! /bin/bash
: '
runs coredns and displays debug information
'

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <DEBUG>" >&2
    exit 1
fi
DEBUG=$1

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
version_file=/OQS-bind/VERSION
version=0
if [[ -f $version_file ]]; then
    version=$(<$version_file)
fi
echo "bind version: $version"
echo "named version: $(named -v)"

# Print CoreDNS version
echo -e "\nCoreDNS version:"
if [ -x /opt/coredns/coredns ]; then
    /opt/coredns/coredns --version
else
    echo "CoreDNS not found at /opt/coredns/coredns"
fi

# print /opt/coredns/config.json
echo -e "-------------------------------------"
echo -e "|          config.json              |"
echo -e "-------------------------------------"
if [ -f "/opt/coredns/config.json" ]; then
    echo -e "\nContents of /opt/coredns/config.json:"
    cat "/opt/coredns/config.json"
else 
    echo "config.json not found!"
    exit
fi

# print /opt/coredns/CoreFile
echo -e "-------------------------------------"
echo -e "|          Core File                 |"
echo -e "-------------------------------------"
if [ -f "/opt/coredns/CoreFile" ]; then
    echo -e "\nContents of /opt/coredns/CoreFile:"
    cat "/opt/coredns/CoreFile"
else 
    echo "CoreFile not found!"
    exit
fi

dir=$(jq -r '.Config Directory' /opt/coredns/config.json)
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
done < <(find "$dir" -type f -name "K*.private")
echo -e "---------------------------"
read -p "do you want to run bind with these settings? (Y/N): " choice

# Check the user's input
if [[ "$choice" =~ ^[Yy]$ ]]; then
    pkill coredns
    pkill tcpdump
    if [ "$DEBUG" = "true" ]; then
        echo "DEBUG MODE"
        tcpdump -i any 'port 53 and (udp or tcp)' -w capture.pcap &
        gdb --batch -ex "run" -ex "bt" -ex "quit" --args $dir/coredns -conf $dir/CoreFile
    else
        named -d 3
        $dir/coredns -conf $dir/CoreFile
    fi
else
    echo "aborting..."
    exit 1
fi