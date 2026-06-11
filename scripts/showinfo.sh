#!/bin/bash

# Print OpenSSL version
echo "OpenSSL version:"
openssl version

# Print active OpenSSL providers
echo -e "\nActive OpenSSL providers:"
openssl list -providers

# Print Go version
echo -e "\nGo version:"
go version

# Print OQS-BIND version (assuming it's installed and in PATH)
echo -e "\nOQS-BIND version:"
if command -v oqs-bind >/dev/null 2>&1; then
    oqs-bind --version
else
    echo "OQS-BIND not found in PATH"
fi

# Print CoreDNS version
echo -e "\nCoreDNS version:"
if [ -x /opt/coredns/coredns ]; then
    /opt/coredns/coredns --version
else
    echo "CoreDNS not found at /opt/coredns/coredns"
fi