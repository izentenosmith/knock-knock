import json
import os
import socket
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


POD = os.environ.get("POD_NAME") or socket.gethostname()
NODE = os.environ.get("NODE_NAME") or "local"
VERSION = os.environ.get("VERSION") or "dev"
STARTED = now()
served = 0
lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # keep-alive, like the other three backends

    def do_GET(self):
        global served
        t0 = time.perf_counter_ns()
        received = now()
        path = self.path.split("?")[0]
        if path == "/healthz":
            return self.reply("text/plain", b"ok")
        if path != "/api/knock":
            return self.reply("text/plain", b"not found", 404)
        with lock:
            served += 1
            n = served
        sig = {
            "lang": "py", "version": VERSION, "pod": POD, "node": NODE,
            "pod_started": STARTED, "served": n, "received_at": received,
            "responded_at": now(), "took_us": (time.perf_counter_ns() - t0) // 1000,
        }
        self.reply("application/json", json.dumps(sig).encode())

    def reply(self, content_type, body, status=200):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # quiet, like the other three
        pass


ThreadingHTTPServer(("", 8080), Handler).serve_forever()
