#!/bin/bash

# Check if directory name is provided
if [ -z "$1" ]; then
    echo "Error: Please provide a directory name as an argument."
    exit 1
fi

required_files=("cert.pem" "key.pem" "CoreFile")
missing_files=()

for file in "${required_files[@]}"; do
    if [ ! -f "$1/$file" ]; then
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -ne 0 ]; then
    echo "Error: The following required files are missing:"
    for file in "${missing_files[@]}"; do
        echo "- $file"
    done
    exit 1
fi

echo "Copying files to /opt/coredns..."
sudo cp "$1/cert.pem" "$1/key.pem" "$1/CoreFile" /opt/coredns/

# print root DS hash
if [ -f "$1/dsset-." ]; then
    echo "SHA256 sum of dsset-.:"
    sha256sum "$1/dsset-."
else
    echo "Error: dsset-. does not exist in the specified directory."
    exit 1
fi