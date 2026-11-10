const BASE_DOMAIN = "hydra-dns.au";
const LOCATION = "sydney";

const ALGORITHMS = [
  { id: "p256-falcon512", label: "P256_FALCON512", pqc: true },
  { id: "falcon512", label: "FALCON512", pqc: true },
  { id: "falcon1024", label: "FALCON1024", pqc: true },
  { id: "rsa3072-falcon512", label: "RSA3072_FALCON512", pqc: true },
  { id: "mldsa44", label: "MLDSA44", pqc: true },
  { id: "p256-mldsa44", label: "P256_MLDSA44", pqc: true },
  { id: "rsa3072-mldsa44", label: "RSA3072_MLDSA44", pqc: true },
  { id: "mldsa65", label: "MLDSA65", pqc: true },
  { id: "p384-mldsa65", label: "P384_MLDSA65", pqc: true },
  { id: "mldsa87", label: "MLDSA87", pqc: true },
  { id: "p521-mldsa87", label: "P521_MLDSA87", pqc: true },
  { id: "slhdsasha2128s", label: "SLHDSASHA2128S", pqc: true },
  { id: "p256-slhdsasha2128s", label: "P256_SLHDSASHA2128S", pqc: true },
  { id: "rsa3072-slhdsasha2128s", label: "RSA3072_SLHDSASHA2128S", pqc: true },
  { id: "mayo1", label: "MAYO1", pqc: true },
  { id: "p256-mayo1", label: "P256_MAYO1", pqc: true },
  { id: "snova2454", label: "SNOVA2454", pqc: true },
  { id: "p256-snova2454", label: "P256_SNOVA2454", pqc: true },
  { id: "ecdsap256sha256", label: "ECDSAP256SHA256", pqc: false },
  { id: "ed25519", label: "ED25519", pqc: false },
  { id: "rsasha256", label: "RSASHA256", pqc: false }
];

const CLIENTS = {
  doq: { label: "DNS over QUIC (DoQ)", defaultPort: 853, scheme: "quic" },
  dot: { label: "DNS over TLS (DoT)", defaultPort: 8853, scheme: "tls" },
  doudp: { label: "DNS over UDP (DoUDP)", defaultPort: 53, scheme: "udp" },
  dotcp: { label: "DNS over TCP (DoTCP)", defaultPort: 53, scheme: "tcp" }
};

const CLIENT_ORDER = ["doq", "dot", "doudp", "dotcp"];

const Q_TYPES = ["A", "AAAA", "MX", "TXT", "NS", "SOA", "CNAME", "PTR", "SRV", "DNSKEY", "DS", "RRSIG", "CAA", "HTTPS", "SVCB", "ANY"];

const CLASSICAL_ALGORITHMS = ALGORITHMS.filter((a) => !a.pqc).map((a) => a.id);
const CLOUDFLARE_ALGORITHMS = CLASSICAL_ALGORITHMS.concat(["mldsa44"]);

const RESOLVERS = {
  ours: {
    value: "ours",
    ip: "16.50.166.15",
    name: "Hydra PQC resolver (ours)",
    algorithms: ALGORITHMS.map((a) => a.id),
    clients: CLIENT_ORDER.slice()
  },
  cloudflare: {
    value: "cloudflare",
    ip: "1.1.1.1",
    name: "Cloudflare",
    algorithms: CLOUDFLARE_ALGORITHMS,
    clients: ["dot", "doudp", "dotcp"]
  },
  quad9: {
    value: "quad9",
    ip: "9.9.9.9",
    name: "Quad9",
    algorithms: CLASSICAL_ALGORITHMS,
    clients: ["dot", "doudp", "dotcp"]
  },
  google: {
    value: "google",
    ip: "8.8.8.8",
    name: "Google",
    algorithms: CLASSICAL_ALGORITHMS,
    clients: ["doudp", "dotcp"]
  }
};

const RESOLVER_ORDER = ["ours", "cloudflare", "quad9", "google"];

const state = {
  resolver: "ours",
  algorithm: "p256-falcon512",
  client: "doq",
  port: CLIENTS.doq.defaultPort,
  subdomain: "test",
  qtype: "A",
  override: ""
};

const els = {
  backend: document.getElementById("backend-status"),
  resolver: document.getElementById("resolver"),
  resolverInfo: document.getElementById("resolver-info"),
  algorithm: document.getElementById("algorithm"),
  algorithmWarning: document.getElementById("algorithm-warning"),
  client: document.getElementById("client"),
  port: document.getElementById("port"),
  clientWarning: document.getElementById("client-warning"),
  subdomain: document.getElementById("subdomain"),
  qtype: document.getElementById("qtype"),
  override: document.getElementById("override"),
  nameWarning: document.getElementById("name-warning"),
  preview: document.getElementById("query-preview"),
  cli: document.getElementById("cli-preview"),
  run: document.getElementById("run"),
  results: document.getElementById("results"),
  resultDetails: document.getElementById("result-details"),
  resultRaw: document.getElementById("result-raw")
};

function qname() {
  if (state.override.trim() !== "") return state.override.trim();
  return `${state.subdomain}.${state.algorithm}-${LOCATION}.${BASE_DOMAIN}`;
}

function fillSelect(select, options, current) {
  select.innerHTML = "";
  for (const opt of options) {
    const el = document.createElement("option");
    el.value = opt.value;
    el.textContent = opt.label;
    if (opt.value === current) el.selected = true;
    select.appendChild(el);
  }
}

function renderResolverInfo() {
  const r = RESOLVERS[state.resolver];
  const algoTags = ALGORITHMS.map((a) => {
    const supported = r.algorithms.includes(a.id);
    return `<span class="tag ${supported ? "supported" : "unsupported"}" title="${a.label}">${a.id}</span>`;
  }).join("");
  const clientTags = CLIENT_ORDER.map((c) => {
    const supported = r.clients.includes(c);
    return `<span class="tag ${supported ? "supported" : "unsupported"}">${CLIENTS[c].label}</span>`;
  }).join("");
  els.resolverInfo.innerHTML = `
    <h3>Supported PQC / DNSSEC algorithms</h3>
    <div class="tag-list">${algoTags}</div>
    <h3>Supported clients</h3>
    <div class="tag-list">${clientTags}</div>`;
}

function cliCommand() {
  const r = RESOLVERS[state.resolver];
  const scheme = CLIENTS[state.client].scheme;
  const server = scheme === "udp" || scheme === "tcp"
    ? `@${r.ip}:${state.port}`
    : `@${scheme}://${r.ip}:${state.port}`;
  const tcpFlag = scheme === "tcp" ? " --tcp" : "";
  return `q ${server} ${qname()} ${state.qtype} -d${tcpFlag}`;
}

function renderPreview() {
  const r = RESOLVERS[state.resolver];
  const c = CLIENTS[state.client];
  const rows = [
    ["Resolver", `${r.name} — ${r.ip}:${state.port}`],
    ["Client / transport", `${c.label} (${c.scheme}://)`],
    ["QNAME", qname()],
    ["QTYPE", `${state.qtype} (DO bit set for DNSSEC)`]
  ];
  els.preview.innerHTML = rows
    .map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`)
    .join("");
  els.cli.textContent = cliCommand();
}

const LABEL_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/;
const DOMAIN_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\.?$/;

function validate() {
  const r = RESOLVERS[state.resolver];
  const c = CLIENTS[state.client];
  const algo = ALGORITHMS.find((a) => a.id === state.algorithm);

  let algoMsg = "";
  if (!r.algorithms.includes(state.algorithm)) {
    algoMsg = algo.pqc
      ? `${r.name} (${r.ip}) does not support the PQC algorithm ${algo.label}; only classical DNSSEC is available.`
      : `${r.name} (${r.ip}) does not support ${algo.label}.`;
  }
  let clientMsg = "";
  if (!r.clients.includes(state.client)) {
    clientMsg = `${r.name} (${r.ip}) does not support ${c.label}.`;
  }
  let nameMsg = "";
  if (state.override.trim() !== "") {
    if (!DOMAIN_RE.test(state.override.trim())) {
      nameMsg = `"${state.override}" is not a valid domain name.`;
    }
  } else if (!LABEL_RE.test(state.subdomain)) {
    nameMsg = `"${state.subdomain}" is not a valid subdomain label.`;
  }

  els.algorithmWarning.textContent = algoMsg;
  els.algorithmWarning.classList.toggle("hidden", !algoMsg);
  els.clientWarning.textContent = clientMsg;
  els.clientWarning.classList.toggle("hidden", !clientMsg);
  els.nameWarning.textContent = nameMsg;
  els.nameWarning.classList.toggle("hidden", !nameMsg);
  els.run.disabled = Boolean(algoMsg || clientMsg || nameMsg);

  return !algoMsg && !clientMsg && !nameMsg;
}

function updateAll() {
  renderResolverInfo();
  renderPreview();
  validate();
}

async function checkBackend() {
  try {
    const res = await fetch("/api/status");
    const data = await res.json();
    const tools = Object.entries(data.tools)
      .map(([t, ok]) => `${t} ${ok ? "✓" : "✗"}`)
      .join(", ");
    els.backend.innerHTML = `Local backend: <span class="status-ok">running</span> — DNS clients: ${tools}`;
  } catch (e) {
    els.backend.innerHTML = `Local backend: <span class="status-err">not running</span> — start it with <code>python3 demo-website/server.py</code>, then reload. Queries cannot be executed without it.`;
  }
}

async function runQuery() {
  if (!validate()) return;
  const r = RESOLVERS[state.resolver];
  els.run.disabled = true;
  els.run.textContent = "Querying…";
  els.results.classList.remove("hidden");
  els.resultDetails.innerHTML = "<dt>Status</dt><dd>running…</dd>";
  els.resultRaw.textContent = "";

  const params = new URLSearchParams({
    resolver: r.ip,
    port: String(state.port),
    transport: state.client,
    qname: qname(),
    qtype: state.qtype
  });

  try {
    const res = await fetch(`/api/query?${params}`);
    const data = await res.json();
    renderResult(data);
  } catch (e) {
    els.resultDetails.innerHTML = `<dt>Status</dt><dd><span class="status-err">backend unreachable</span></dd>
      <dt>Hint</dt><dd>Start the local backend with <code>python3 demo-website/server.py</code> and reload this page.</dd>`;
    els.resultRaw.textContent = String(e);
  } finally {
    els.run.disabled = false;
    els.run.textContent = "Run query";
    els.results.scrollIntoView({ behavior: "smooth" });
  }
}

function renderResult(data) {
  const timeMs = data.query_time_ms != null ? data.query_time_ms : data.wall_time_ms;
  const statusOk = data.ok && data.rcode === "NOERROR";
  const rows = [
    ["Status", data.error
      ? `<span class="status-err">${data.error}</span>`
      : `<span class="${statusOk ? "status-ok" : "status-err"}">${data.rcode || "no rcode"} (exit ${data.exit_code})</span>`],
    ["Response time", timeMs != null ? `${timeMs} ms` : "n/a"],
    ["DNS client", data.tool || "n/a"],
    ["Command", data.command || cliCommand()],
    ["Resolver", `${RESOLVERS[state.resolver].ip}:${state.port} via ${CLIENTS[state.client].label}`],
    ["Question", `${qname()} ${state.qtype}`]
  ];
  els.resultDetails.innerHTML = rows
    .map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`)
    .join("");
  els.resultRaw.textContent = data.output || data.error || "(no output)";
}

function init() {
  fillSelect(els.resolver, RESOLVER_ORDER.map((k) => ({
    value: k, label: `${RESOLVERS[k].name} — ${RESOLVERS[k].ip}`
  })), state.resolver);

  fillSelect(els.algorithm, ALGORITHMS.map((a) => ({
    value: a.id, label: `${a.label}${a.pqc ? " (PQC)" : " (classical)"}`
  })), state.algorithm);

  fillSelect(els.client, CLIENT_ORDER.map((k) => ({
    value: k, label: CLIENTS[k].label
  })), state.client);

  fillSelect(els.qtype, Q_TYPES.map((t) => ({ value: t, label: t })), state.qtype);

  els.port.value = state.port;
  els.subdomain.value = state.subdomain;
  els.override.value = state.override;

  els.resolver.addEventListener("change", () => {
    state.resolver = els.resolver.value;
    updateAll();
  });

  els.algorithm.addEventListener("change", () => {
    state.algorithm = els.algorithm.value;
    updateAll();
  });

  els.client.addEventListener("change", () => {
    state.client = els.client.value;
    state.port = CLIENTS[state.client].defaultPort;
    els.port.value = state.port;
    updateAll();
  });

  els.port.addEventListener("change", () => {
    const p = parseInt(els.port.value, 10);
    if (p >= 1 && p <= 65535) {
      state.port = p;
    }
    updateAll();
  });

  els.subdomain.addEventListener("input", () => {
    state.subdomain = els.subdomain.value.trim().toLowerCase();
    updateAll();
  });

  els.qtype.addEventListener("change", () => {
    state.qtype = els.qtype.value;
    updateAll();
  });

  els.override.addEventListener("input", () => {
    state.override = els.override.value.trim().toLowerCase();
    updateAll();
  });

  els.run.addEventListener("click", runQuery);

  checkBackend();
  updateAll();
}

document.addEventListener("DOMContentLoaded", init);
