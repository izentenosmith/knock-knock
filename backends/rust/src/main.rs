use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tiny_http::{Header, Method, Response, Server};

fn env(key: &str, fallback: &str) -> String {
    std::env::var(key).ok().filter(|v| !v.is_empty()).unwrap_or_else(|| fallback.to_string())
}

// UTC ISO 8601 with microseconds, without a date crate (civil_from_days, Howard Hinnant).
fn iso(t: SystemTime) -> String {
    let d = t.duration_since(UNIX_EPOCH).unwrap();
    let (days, secs) = (d.as_secs() / 86400, d.as_secs() % 86400);
    let z = days + 719_468;
    let (era, doe) = (z / 146_097, z % 146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = era * 400 + yoe + u64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{:06}Z",
        secs / 3600, secs % 3600 / 60, secs % 60, d.subsec_micros()
    )
}

// distroless has no shell or curl, so the binary is its own healthcheck.
fn healthy() -> bool {
    let check = || -> std::io::Result<bool> {
        let mut s = TcpStream::connect("127.0.0.1:8080")?;
        s.set_read_timeout(Some(Duration::from_secs(2)))?;
        s.write_all(b"GET /healthz HTTP/1.0\r\n\r\n")?;
        let mut status = [0u8; 12]; // "HTTP/1.x 200"
        s.read_exact(&mut status)?;
        Ok(&status[9..] == b"200")
    };
    check().unwrap_or(false)
}

fn main() {
    if std::env::args().nth(1).as_deref() == Some("--healthcheck") {
        std::process::exit(if healthy() { 0 } else { 1 });
    }

    let host = std::fs::read_to_string("/proc/sys/kernel/hostname").unwrap_or_default();
    let pod = env("POD_NAME", host.trim());
    let node = env("NODE_NAME", "local");
    let version = env("VERSION", "dev");
    let started = iso(SystemTime::now());
    let served = AtomicU64::new(0);
    let server = Server::http("0.0.0.0:8080").unwrap();

    std::thread::scope(|s| {
        for _ in 0..4 {
            s.spawn(|| {
                for req in server.incoming_requests() {
                    let t0 = Instant::now();
                    let received = iso(SystemTime::now());
                    let path = req.url().split('?').next().unwrap_or("");
                    let (status, content_type, body) = match (req.method(), path) {
                        (Method::Get, "/healthz") => (200, "text/plain", "ok".to_string()),
                        (Method::Get, "/api/knock") => {
                            let n = served.fetch_add(1, Ordering::Relaxed) + 1;
                            // {:?} quotes and escapes a string: valid JSON for these values.
                            let body = format!(
                                r#"{{"lang":"rust","version":{version:?},"pod":{pod:?},"node":{node:?},"pod_started":{started:?},"served":{n},"received_at":{received:?},"responded_at":{:?},"took_us":{}}}"#,
                                iso(SystemTime::now()),
                                t0.elapsed().as_micros()
                            );
                            (200, "application/json", body)
                        }
                        _ => (404, "text/plain", "not found".to_string()),
                    };
                    let header = Header::from_bytes("Content-Type", content_type).unwrap();
                    let _ = req.respond(Response::from_string(body).with_status_code(status).with_header(header));
                }
            });
        }
    });
}
