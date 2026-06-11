#!/bin/bash

# Check if directory name is provided
if [ -z "$1" ]; then
    echo "Error: Please provide a directory name as an argument."
    exit 1
fi

# Step 1: Check if config.json exists and print its output
if [ -f "$1/config.json" ]; then
    echo "Contents of config.json:"
    cat "$1/config.json"
else
    echo "Error: config.json does not exist in the specified directory."
    exit 1
fi

# Step 2: Copy files to /opt/coredns with sudo
required_files=("cert.pem" "key.pem" "db.test.signed" "CoreFile")
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
sudo cp "$1/cert.pem" "$1/key.pem" "$1/db.test.signed" "$1/CoreFile" /opt/coredns/

# Step 3: Print sha256sum of dsset-test.
if [ -f "$1/dsset-example.test." ]; then
    echo "SHA256 sum of dsset-example.test.:"
    sha256sum "$1/dsset-example.test."
else
    echo "Error: dsset-example.test. does not exist in the specified directory."
    exit 1
fi
if [ -f "$1/dsset-test." ]; then
    echo "SHA256 sum of dsset-test.:"
    sha256sum "$1/dsset-test."
    echo "Contents of dsset-test.:"
    cat "$1/dsset-test."
else
    echo "Error: dsset-test. does not exist in the specified directory."
    exit 1
fi
