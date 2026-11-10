# PQC DNSSEC demo website

A dependency-free static website that demonstrates querying the
post-quantum DNSSEC test zones (`test.[scheme]-sydney.hydra-dns.au`)
over different transports against different resolvers.

## Run locally

Open `index.html` directly in a browser, or serve the folder:

```
cd demo-website
python3 -m http.server 8080
```

Then visit <http://localhost:8080>.

## GitHub Pages

Enable GitHub Pages for this repository with the source set to
`/demo-website` on the default branch to publish the demo.

## What it does

1. Pick a resolver: `16.50.166.15` (ours, PQC-capable), `1.1.1.1`
   (Cloudflare) or `8.8.8.8` (Google). The supported PQC algorithms and
   clients (DoQ, DoT, DoUDP, DoTCP) are shown per resolver.
2. Pick a DNSSEC signature scheme (e.g. `p256-falcon512`, `falcon512`,
   `mldsa44`). The QNAME that will be queried becomes
   `test.[scheme]-sydney.hydra-dns.au`.
3. Pick a client: DNS over QUIC (default port 853), DNS over TLS
   (default port 8853), DoUDP or DoTCP. The port can be changed.

The exact query is shown before running. Executing the query shows the
response time and the (simulated) result, since a browser cannot perform
PQC/TLS handshakes itself.
