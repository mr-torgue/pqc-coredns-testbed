# PQC DNSSEC demo website

A static front-end plus a tiny local backend that runs a real DNS client
(`q`, falling back to `kdig`/`dig`) so the browser never has to open raw
sockets itself.

## How it works

- `server.py` (Python 3 standard library only) serves this folder on
  `http://127.0.0.1:8080` and exposes:
  - `GET /api/status` — which DNS clients are installed
  - `GET /api/query?resolver=<ip>&port=<port>&transport=<doq|dot|doudp|dotcp>&qname=<name>`
    — runs `q` (or `kdig`/`dig`) in the background and returns the real
    command, rcode, query time and raw output as JSON
- `index.html` / `app.js` — the front-end. It previews the exact query,
  then calls `/api/query` when you press "Run query" and shows the real
  response time and result.

## Setup

Install a DNS client (q is recommended because it supports DoQ):

```
go install github.com/natesales/q@latest   # or: brew install q
```

`kdig` (from knot-dnsutils) or `dig` (from bind9-utils) work as fallbacks
for DoT/DoUDP/DoTCP.

## Run

```
cd demo-website
python3 server.py
```

Then open <http://127.0.0.1:8080>.

## What it does

1. Pick a resolver: `16.50.166.15` (ours, PQC-capable), `1.1.1.1`
   (Cloudflare, incl. MLDSA44), `9.9.9.9` (Quad9) or `8.8.8.8` (Google).
   The supported PQC algorithms and clients (DoQ, DoT, DoUDP, DoTCP)
   are shown per resolver.
2. Pick a DNSSEC signature scheme (e.g. `p256-falcon512`, `falcon512`,
   `mldsa44`). The QNAME that will be queried becomes
   `[subdomain].[scheme]-sydney.hydra-dns.au`.
3. Pick a client: DNS over QUIC (default port 853), DNS over TLS
   (default port 8853), DoUDP or DoTCP. The port can be changed.
4. Set the subdomain label (default `test`, e.g. `xyz` queries
   `xyz.[scheme]-sydney.hydra-dns.au`), the query type (A, AAAA, MX,
   DNSKEY, ...), or a full query domain (e.g. `google.com`) which
   overrides the subdomain+scheme pattern entirely.

The exact query (and the `q` command the backend will run) is shown
before submitting. Executing sends the query through the local DNS
client and displays the real response time, rcode and answer.
