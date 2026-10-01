Creates a testbed that sets up a resolver and three name servers using CoreDNS.

# Installation
The following will install liboqs, oqs-provider, openssl, coredns (openssl version), go, oqs-bind, and dependencies:
```
curl -L -O https://github.com/mr-torgue/pqc-coredns-testbed/setup.sh && ./setup
```
## Vagrant
Use Vagrant to spanw VM's locally: `vagrant up`.
In the VM run the installation script.

## Enabling Prometheus and Grafana
Install with:
```
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
```

Add the following to `/etc/prometheus/prometheus.yml` to enable CoreDNS logging in Prometheus:
```
  - job_name: coredns
    honor_timestamps: true
    scrape_interval: 15s
    scrape_timeout: 10s
    metrics_path: /metrics
    scheme: http
    follow_redirects: true
    enable_http2: true
    static_configs:
    - targets:
      - localhost:9153 
```
Go to the Grafana instance (IP:3000) and add Prometheus as a data source.
Install the [node-exporter](https://grafana.com/grafana/dashboards/1860-node-exporter-full/) and [CoreDNS](https://grafana.com/grafana/dashboards/14981-coredns/) dashboards.

# How to Use
The easiest way is to use the provided scripts.

## Configuration
We have several predefined configurations:
- NS-example.test: Nameserver for example.test domain
- NS-test: Namserver for .test TLD
- NS-Root: Nameserver for root
- Resolver: resolver
- NS-hydra-dns.au: Nameserver for (subdomain.)hydra-dns.au. Uses real TLD and root servers. Can be used for different subdomains as well.
Running the `config.sh` script will generate all the necessary config files to run your nameserver or resolver.
This includes:
1. DS records to be saved on the parent server
2. TLS certificates
3. Signed zones
4. CoreFile
5. Systemd service file
Basically, the script will generate a folder that is seen as one configuration.
When running, this configuration needs to be specfied. 
This way can switch between configuration easily.
NS-example.test will generate the files for `example.test`. 
NS-hydra-dns.au is slightly different and will generate files for `[loc].hydra-dns.au`.
Using `-h` option will show all parameters. 

## Running
Use `run.sh` to run coredns. 
Use `-c [config]` to specify a configuration.
Using `-h` option will show all parameters. 

## Monitoring
Use `monitor.sh` to sart monitoring. 
This includes CPU/memory/network monitoring using sar, pcap dumps, and logging queries. 
Using `-h` option will show all parameters. 

# Manual Setup
Not recommended, but possible if you know what you are doing.

## Using DoQ and DoT
DoT and DoQ require TLS certificates. Which can be generated with `sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout key.pem -out cert.pem`. 
During set up, these certificates will be generated and stored in `/opt/coredns`.

> [!NOTE]
> There is currently no way to configure which signature scheme to use.

> [!NOTE]
> You might need to run without verifying the TLS signature because the certificate is self-signed.
> For the resolver, this can be disabled by setting `notlsverify`.

## DNSSEC
The name servers don't use the DNSSEC or Sign plugin, but merely use a signed zone.
To generate a zone, we first need to generate keys and then sign the zone.
Assuming that OQS-BIND is installed this works as follows:
```
sudo dnssec-keygen -a P256_FALCON512 -n ZONE .
sudo dnssec-signzone -o . -N INCREMENT -t -K . -S db.root
```

> [!NOTE]
> Make sure you are in the same directory as the keys and zone file that needs to be signed.

> [!NOTE]
> Make sure to include the DS record in the parent zone or trust anchor.

## Custom Root Zones and Trust Anchors
When running a custom root server, make sure to load the proper root file and trust anchor on the resolver.
On the resolver, the files can be specified with:
```
resolver {
    hints "named.test.root"
    anchor "root-anchors.test.xml"
}
```

# To Do
1. Fix redundancy in scripts: most scripts are very similar
2. Add an option to run coredns as user instead of root

# Trouble Shooting
1. Check if liboqs is enabled: `openssl list -providers` if no oqs-provider, enable it in `/usr/local/ssl/openssl.cnf`.