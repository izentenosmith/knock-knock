# A stand-in for the compose stack at the smoke test's boundary: GET /api/knock answers
# contract-valid signatures, rotating go -> python -> rust -> ts. <versions> is one version,
# or a comma-separated list cycled answer by answer (to fake a backend that ignored VERSION).
# Usage: python3 fake_api.py <port> <versions>
import itertools, json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port, versions = int(sys.argv[1]), itertools.cycle(sys.argv[2].split(","))
langs = itertools.cycle(["go", "python", "rust", "ts"])
served = itertools.count(1)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        lang = next(langs)
        body = json.dumps({
            "lang": lang, "version": next(versions), "pod": f"fake-{lang}", "node": "local",
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
