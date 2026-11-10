const BASE_DOMAIN = "hydra-dns.au";
const LOCATION = "sydney";
const TEST_ANSWER_IP = "42.42.42.42";

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

const PQC_ALGORITHMS = ALGORITHMS.filter((a) => a.pqc).map((a) => a.id);
const CLASSICAL_ALGORITHMS = ALGORITHMS.filter((a) => !a.pqc).map((a) => a.id);

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

const RESOLVER_ORDER = ["ours", "cloudflare", "google"];

const state = {
  resolver: "ours",
  algorithm: "p256-falcon512",
  client: "doq",
  port: CLIENTS.doq.defaultPort
};

const els = {
  resolver: document.getElementById("resolver"),
  resolverInfo: document.getElementById("resolver-info"),
  algorithm: document.getElementById("algorithm"),
  algorithmWarning: document.getElementById("algorithm-warning"),
  client: document.getElementById("client"),
  port: document.getElementById("port"),
  clientWarning: document.getElementById("client-warning"),
  preview: document.getElementById("query-preview"),
  cli: document.getElementById("cli-preview"),
  run: document.getElementById("run"),
  results: document.getElementById("results"),
  resultDetails: document.getElementById("result-details"),
  resultRaw: document.getElementById("result-raw")
};

function qname() {
  return `test.${state.algorithm}-${LOCATION}.${BASE_DOMAIN}`;
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

function renderPreview() {
  const r = RESOLVERS[state.resolver];
  const c = CLIENTS[state.client];
  const rows = [
    ["Resolver", `${r.name} — ${r.ip}:${state.port}`],
    ["Client / transport", `${c.label} (${c.scheme}://)`],
    ["QNAME", qname()],
    ["QTYPE", "A (DNSSEC requested, DO bit set)"]
  ];
  els.preview.innerHTML = rows
    .map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`)
    .join("");

  const q = qname();
  const cliByClient = {
    doq: `doq @${r.ip} -p ${state.port} ${q} A +dnssec`,
    dot: `dig +tls @${r.ip} -p ${state.port} ${q} A +dnssec`,
    doudp: `dig @${r.ip} -p ${state.port} ${q} A +dnssec`,
    dotcp: `dig +tcp @${r.ip} -p ${state.port} ${q} A +dnssec`
  };
  els.cli.textContent = cliByClient[state.client];
}

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

  els.algorithmWarning.textContent = algoMsg;
  els.algorithmWarning.classList.toggle("hidden", !algoMsg);
  els.clientWarning.textContent = clientMsg;
  els.clientWarning.classList.toggle("hidden", !clientMsg);
  els.run.disabled = Boolean(algoMsg || clientMsg);

  return !algoMsg && !clientMsg;
}

function updateAll() {
  renderResolverInfo();
  renderPreview();
  validate();
}

function simulate() {
  const r = RESOLVERS[state.resolver];
  const c = CLIENTS[state.client];
  const algo = ALGORITHMS.find((a) => a.id === state.algorithm);

  const base = { ours: [35, 140], cloudflare: [8, 45], google: [10, 50] }[state.resolver];
  const transportFactor = { doq: 1.15, dot: 1.25, doudp: 1.0, dotcp: 1.3 }[state.client];
  const ms = Math.round((base[0] + Math.random() * (base[1] - base[0])) * transportFactor * 10) / 10;

  const ad = state.resolver === "ours" || !algo.pqc;
  const validation = algo.pqc
    ? `validated with ${algo.label} (post-quantum)`
    : `validated with ${algo.label} (classical)`;

  const details = [
    ["Status", `<span class="status-ok">NOERROR</span>`],
    ["Response time", `${ms} ms`],
    ["Resolver", `${r.name} — ${r.ip}:${state.port} over ${c.label}`],
    ["Question", `${qname()} A`],
    ["Answer", `${qname()} 604800 IN A ${TEST_ANSWER_IP}`],
    ["DNSSEC", `AD=${ad ? "1" : "0"} — ${validation}`]
  ];
  els.resultDetails.innerHTML = details
    .map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`)
    .join("");

  els.resultRaw.textContent = [
    `;; Query sent to ${r.ip}:${state.port} via ${c.scheme}:// — ${qname()} A +dnssec`,
    `;; Got answer:`,
    `;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: ${1000 + Math.floor(Math.random() * 9000)}`,
    `;; flags: qr rd ra ${ad ? "ad" : ""}; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1`,
    ``,
    `;; QUESTION SECTION:`,
    `;${qname()}.\t\tIN\tA`,
    ``,
    `;; ANSWER SECTION:`,
    `${qname()}.\t604800\tIN\tA\t${TEST_ANSWER_IP}`,
    ``,
    `;; DNSSEC: ${validation}; AD bit ${ad ? "set" : "not set"}`,
    `;; Query time: ${ms} ms`,
    `;; SERVER: ${r.ip}#${state.port}(${c.scheme})`,
    `;; WHEN: ${new Date().toUTCString()}`
  ].join("\n");

  els.results.classList.remove("hidden");
  els.results.scrollIntoView({ behavior: "smooth" });
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

  els.port.value = state.port;

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

  els.run.addEventListener("click", () => {
    if (validate()) simulate();
  });

  updateAll();
}

document.addEventListener("DOMContentLoaded", init);
