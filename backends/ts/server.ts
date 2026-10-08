import { createServer } from "node:http";
import { hostname } from "node:os";

// Date stops at milliseconds, so the microseconds come from the high-resolution clock.
// Re-anchor to Date if the wall clock jumped (NTP, host sleep) since the last call.
let origin = performance.timeOrigin;
function now(): string {
  if (Math.abs(origin + performance.now() - Date.now()) > 1) origin = Date.now() - performance.now();
  const t = origin + performance.now();
  const us = String(Math.floor((t % 1) * 1000)).padStart(3, "0");
  return new Date(Math.floor(t)).toISOString().replace("Z", `${us}Z`);
}

const pod = process.env.POD_NAME || hostname();
const node = process.env.NODE_NAME || "local";
const version = process.env.VERSION || "dev";
const started = now();
let served = 0; // one thread (the event loop), so a plain counter is safe

createServer((req, res) => {
  const t0 = process.hrtime.bigint();
  const received = now();
  const path = req.url?.split("?")[0];
  if (req.method === "GET" && path === "/healthz") {
    res.writeHead(200, { "Content-Type": "text/plain" }).end("ok");
  } else if (req.method === "GET" && path === "/api/knock") {
    served++;
    const sig = {
      lang: "ts", version, pod, node, pod_started: started, served, received_at: received,
      responded_at: now(), took_us: Number((process.hrtime.bigint() - t0) / 1000n),
    };
    res.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify(sig));
  } else {
    res.writeHead(404, { "Content-Type": "text/plain" }).end("not found");
  }
}).listen(8080);
