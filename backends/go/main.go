package main

import (
	"encoding/json"
	"net/http"
	"os"
	"sync/atomic"
	"time"
)

const iso = "2006-01-02T15:04:05.000000Z"

type signature struct {
	Lang        string `json:"lang"`
	Version     string `json:"version"`
	Pod         string `json:"pod"`
	Node        string `json:"node"`
	PodStarted  string `json:"pod_started"`
	Served      uint64 `json:"served"`
	ReceivedAt  string `json:"received_at"`
	RespondedAt string `json:"responded_at"`
	TookUs      int64  `json:"took_us"`
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	// scratch has no shell or curl, so the binary is its own healthcheck.
	if len(os.Args) > 1 && os.Args[1] == "--healthcheck" {
		resp, err := (&http.Client{Timeout: 2 * time.Second}).Get("http://127.0.0.1:8080/healthz")
		if err != nil || resp.StatusCode != http.StatusOK {
			os.Exit(1)
		}
		return
	}

	host, _ := os.Hostname()
	pod, node, version := env("POD_NAME", host), env("NODE_NAME", "local"), env("VERSION", "dev")
	started := time.Now().UTC().Format(iso)
	var served atomic.Uint64

	http.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})
	http.HandleFunc("GET /api/knock", func(w http.ResponseWriter, r *http.Request) {
		received := time.Now() // carries a monotonic reading, so time.Since below is monotonic
		sig := signature{
			Lang: "go", Version: version, Pod: pod, Node: node, PodStarted: started,
			Served:      served.Add(1),
			ReceivedAt:  received.UTC().Format(iso),
			RespondedAt: time.Now().UTC().Format(iso),
			TookUs:      time.Since(received).Microseconds(),
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(sig)
	})
	http.ListenAndServe(":8080", nil)
}
