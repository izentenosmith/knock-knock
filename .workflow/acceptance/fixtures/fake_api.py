# A stand-in for the compose stack at the smoke test's boundary: GET /api/knock answers
# contract-valid signatures, rotating go -> python -> rust -> ts. <versions> is one version,
# or a comma-separated list cycled answer by answer (to fake a backend that ignored VERSION).
# [nodes] works the same way for `node` (default `local`, the value outside Kubernetes).
# Usage: python3 fake_api.py <port> <versions> [nodes]
import itertools, json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port, versions = int(sys.argv[1]), itertools.cycle(sys.argv[2].split(","))
nodes = itertools.cycle((sys.argv[3] if len(sys.argv) > 3 else "local").split(","))
langs = itertools.cycle(["go", "python", "rust", "ts"])
served = itertools.count(1)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        lang = next(langs)
        body = json.dumps({
            "lang": lang, "version": next(versions), "pod": f"fake-{lang}", "node": next(nodes),
            "pod_started": "2026-01-01T00:00:00.000000Z", "served": next(served),
            "received_at": "2026-01-01T00:00:01.000000Z",
            "responded_at": "2026-01-01T00:00:01.000010Z", "took_us": 10,
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
