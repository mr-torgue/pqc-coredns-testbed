Creates a testbed that sets up a resolver and three name servers using CoreDNS.

# Installation
```
curl -L -O https://github.com/mr-torgue/pqc-coredns-testbed/setup.sh
./setup [nameserver/resolver]
```
## Vagrant
Use Vagrant to spanw VM's locally: `vagrant up`.
In the VM run the instllation script.

## Configuration 
Configurations can be setup


Run coredns with `cd /opt/coredns && ./coredns -conf CoreFile`.

## Enabling Prometheus and Grafana
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


# Using DoQ and DoT
DoT and DoQ require TLS certificates. Which can be generated with `sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout key.pem -out cert.pem`. 
During set up, these certificates will be generated and stored in `/opt/coredns`.

> [!NOTE]
> There is currently no way to configure which signature scheme to use.

> [!NOTE]
> You might need to run without verifying the TLS signature because the certificate is self-signed.
> For the resolver, this can be disabled by setting `notlsverify`.

# DNSSEC
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

# Custom Root Zones and Trust Anchors
When running a custom root server, make sure to load the proper root file and trust anchor on the resolver.
On the resolver, the files can be specified with:
```
resolver {
    hints "named.test.root"
    anchor "root-anchors.test.xml"
}
```

# To Do
1. Display key and zone information in showinfo.sh
2. Add nameserver script that adds NS information for child zones

One major issue is that one typo in the db means the whole zone has to be signed again.
Also, lots of redundancy in the scripts...

# Trouble Shooting
Run `showinfo.sh` to show some basic information.
1. Check if liboqs is enabled: `openssl list -providers` if no oqs-provider, enable it in `/usr/local/ssl/openssl.cnf`.