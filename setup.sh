OPENSSL_VERSION=3.6.2
LIBOQS_VERSION=0.15.0
OQSPROVIDER_VERSION=0.11.0
COREDNS_VERSION=1.14.3
GO_VERSION=1.26.4

# Install pre-requisites
sudo apt update
sudo apt upgrade -y
sudo apt install valgrind nano gdb tcpdump ssh curl cmake gcc pkg-config autoconf automake git build-essential ninja-build libnghttp2-dev libcap-dev libtool libtool-bin libuv1-dev unzip iputils-ping iptables iproute2 liburcu-dev libnetfilter-queue-dev libpcap-dev net-tools traceroute iperf libnl-3-dev libnl-genl-3-dev binutils-dev libreadline6-dev libjemalloc-dev libcmocka-dev libxml2-dev libjson-c-dev binutils -y

# Install OpenSSL
cd ~
curl -L -O https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz
tar -xzvf openssl-${OPENSSL_VERSION}.tar.gz
rm openssl-${OPENSSL_VERSION}.tar.gz
cd openssl-${OPENSSL_VERSION}
./Configure
make
sudo make install
sudo sed -i 's/default = default_sect/default = default_sect\noqsprovider = oqsprovider_sect/' /usr/local/ssl/openssl.cnf
printf '[oqsprovider_sect]\nactivate = 1\n' | sudo tee -a /usr/local/ssl/openssl.cnf >/dev/null
sudo sed -i 's/# activate = 1/activate = 1/' /usr/local/ssl/openssl.cnf
echo "/usr/local/lib64" | sudo tee /etc/ld.so.conf.d/openssl.conf > /dev/null
sudo ln -s /usr/local/lib64/libcrypto.so /usr/lib/x86_64-linux-gnu/libcrypto.so
sudo ldconfig 

# Install liboqs
cd ~
git clone https://github.com/open-quantum-safe/liboqs.git --branch ${LIBOQS_VERSION}
mkdir liboqs/build
cd liboqs/build
cmake -GNinja -DBUILD_SHARED_LIBS=ON ..
ninja -j 1
sudo ninja install

# Install oqs-provider
cd ~
git clone https://github.com/open-quantum-safe/oqs-provider.git --branch ${OQSPROVIDER_VERSION}
cd oqs-provider
cmake -S . -B _build && cmake --build _build && sudo cmake --install _build

# Install OQS-bind for PQC dnssec tools
cd ~
git clone https://github.com/mr-torgue/OQS-bind.git --branch v1.2.1
cd OQS-bind
autoreconf -fi
./configure
make
sudo make install
sudo ldconfig 

# Install go
curl -L -O https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
echo "export PATH=\$PATH:/usr/local/go/bin" | sudo tee -a /etc/profile > /dev/null

# Install CoreDNS
export PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:$PKG_CONFIG_PATH"
echo "export PKG_CONFIG_PATH=\"/usr/local/lib64/pkgconfig:\$PKG_CONFIG_PATH\"" >> ~/.bashrc
cd /tmp
git clone https://github.com/mr-torgue/coredns
cd coredns
sed -i '/^file:file$/i resolver:github.com/mr-torgue/resolver' plugin.cfg
make
sudo mkdir -p /opt/coredns
sudo mv coredns /opt/coredns

# Install prometheus, node_exporter, and Grafana
sudo apt install prometheus prometheus-node-exporter prometheus-bind-exporter -y
sudo systemctl enable prometheus
sudo systemctl start prometheus
sudo systemctl start node_exporter
sudo systemctl enable node_exporter
sudo apt-get install -y adduser libfontconfig1 musl
wget https://dl.grafana.com/grafana-enterprise/release/13.0.2/grafana-enterprise_13.0.2_26816849631_linux_amd64.deb
sudo dpkg -i grafana-enterprise_13.0.2_26816849631_linux_amd64.deb
sudo /bin/systemctl daemon-reload
sudo /bin/systemctl enable grafana-server
sudo /bin/systemctl start grafana-server


# Stop our own stub resolver, we need that port!
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo systemctl mask systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf > /dev/null
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf > /dev/null