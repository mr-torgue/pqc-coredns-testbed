Creates a testbed that sets up a resolver and three name servers using CoreDNS.

For testing, use Vagrant: `vagrant up`.
In the VM run `git clone https://github.com/mr-torgue/pqc-coredns-testbed.git` to get all the scripts.

For production, run `setup.sh` to install the components and copy the `CoreFile` and `zone` to `/opt/coredns`.
Run coredns with `coredns -conf CoreFile`.


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
1. Automate key generation and signing for both TLS and DNSSEC
2. Create a script that automatically convert a root anchor (DS record) into an XML file that can be parsed by the resolver
3. Create options for the ciphers/digital signature schemes
4. Display key and zone information in showinfo.sh

# Trouble Shooting
Run `showinfo.sh` to show some basic information.
1. Check if liboqs is enabled: `openssl list -providers` if no oqs-provider, enable it in `/usr/local/ssl/openssl.cnf`.