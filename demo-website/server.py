import json
import os
import re
import shutil
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HOST = "127.0.0.1"
PORT = 8080
DIR = os.path.dirname(os.path.abspath(__file__))
TIMEOUT_S = 15

TOOLS = ["q", "kdig", "dig"]

CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".md": "text/markdown; charset=utf-8",
}

IPV4_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")
QNAME_RE = re.compile(r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.?$")
TRANSPORTS = {"doq", "dot", "doudp", "dotcp"}
QTYPES = {"A", "AAAA", "MX", "TXT", "NS", "SOA", "CNAME", "PTR", "SRV", "DNSKEY", "DS", "RRSIG", "CAA", "HTTPS", "SVCB", "ANY"}


def available_tools():
    return {t: shutil.which(t) is not None for t in TOOLS}


def tool_supports(tool, transport):
    if tool == "q":
        return True
    if tool == "kdig":
        return transport in {"dot", "doudp", "dotcp"}
    if tool == "dig":
        return transport in {"dot", "doudp", "dotcp"}
    return False


def pick_tool(transport):
    for t in TOOLS:
        if shutil.which(t) and tool_supports(t, transport):
            return t
    return None


def build_command(tool, resolver, port, transport, qname, qtype):
    if tool == "q":
        scheme = {"doq": "quic", "dot": "tls", "doudp": "", "dotcp": ""}[transport]
        server = f"@{scheme}://{resolver}:{port}" if scheme else f"@{resolver}:{port}"
        cmd = [tool, server, qname, qtype, "-d", "--format=raw"]
        if transport == "dotcp":
            cmd.append("--tcp")
        if transport in {"dot", "doq"}:
            cmd.append("-i")
        return cmd
    if tool == "kdig":
        cmd = [tool, f"@{resolver}", "-p", str(port), qname, qtype, "+dnssec"]
        if transport == "dot":
            cmd.append("+tls")
        elif transport == "dotcp":
            cmd.append("+tcp")
        return cmd
    if tool == "dig":
        cmd = [tool, f"@{resolver}", "-p", str(port), qname, qtype, "+dnssec"]
        if transport == "dot":
            cmd.append("+tls")
        elif transport == "dotcp":
            cmd.append("+tcp")
        return cmd
    return None


def run_query(resolver, port, transport, qname, qtype="A"):
    tool = pick_tool(transport)
    if tool is None:
        return {
            "ok": False,
            "error": f"No installed DNS client supports {transport}. Install q (go install github.com/natesales/q@latest) for DoQ/DoT, or kdig/dig.",
        }, 200
    cmd = build_command(tool, resolver, port, transport, qname, qtype)
    start = time.perf_counter()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_S)
        wall_ms = round((time.perf_counter() - start) * 1000, 1)
        out = proc.stdout + proc.stderr
        rcode_m = re.search(r"status:\s*([A-Z]+)", out)
        time_m = re.search(r"[Qq]uery time:\s*(\d+)", out)
        return {
            "ok": proc.returncode == 0,
            "tool": tool,
            "command": " ".join(cmd),
            "exit_code": proc.returncode,
            "rcode": rcode_m.group(1) if rcode_m else None,
            "query_time_ms": int(time_m.group(1)) if time_m else None,
            "wall_time_ms": wall_ms,
            "output": out,
        }, 200
    except subprocess.TimeoutExpired:
        return {"ok": False, "tool": tool, "command": " ".join(cmd),
                "error": f"Query timed out after {TIMEOUT_S}s"}, 200
    except FileNotFoundError:
        return {"ok": False, "error": f"DNS client '{tool}' not found in PATH"}, 200


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/api/status":
            self.send_json({"ok": True, "tools": available_tools()})
            return
        if parsed.path == "/api/query":
            qs = parse_qs(parsed.query)
            resolver = qs.get("resolver", [""])[0]
            qname = qs.get("qname", [""])[0].rstrip(".")
            qtype = qs.get("qtype", ["A"])[0].upper()
            transport = qs.get("transport", [""])[0]
            try:
                port = int(qs.get("port", [""])[0])
            except ValueError:
                port = -1
            if not IPV4_RE.match(resolver) or any(int(o) > 255 for o in resolver.split(".")):
                self.send_json({"ok": False, "error": "Invalid resolver IP"}, 400)
                return
            if not (1 <= port <= 65535):
                self.send_json({"ok": False, "error": "Invalid port"}, 400)
            if transport not in TRANSPORTS:
                self.send_json({"ok": False, "error": "Invalid transport"}, 400)
            if not QNAME_RE.match(qname):
                self.send_json({"ok": False, "error": "Invalid QNAME"}, 400)
                return
            if qtype not in QTYPES:
                self.send_json({"ok": False, "error": "Invalid QTYPE"}, 400)
                return
            obj, code = run_query(resolver, port, transport, qname, qtype)
            self.send_json(obj, code)
            return
        self.serve_static(parsed.path)

    def serve_static(self, path):
        if path in ("/", ""):
            path = "/index.html"
        full = os.path.normpath(os.path.join(DIR, path.lstrip("/")))
        if not full.startswith(DIR) or not os.path.isfile(full):
            self.send_error(404)
            return
        ext = os.path.splitext(full)[1]
        with open(full, "rb") as f:
            body = f.read()
        self.send_response(200)
        self.send_header("Content-Type", CONTENT_TYPES.get(ext, "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Serving demo on http://{HOST}:{PORT} (Ctrl+C to stop)")
    print(f"DNS clients found: {[t for t, ok in available_tools().items() if ok] or 'none'}")
    server.serve_forever()
