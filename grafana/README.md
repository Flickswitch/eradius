# Grafana dashboards for eradius

## `eradius-overview.json`

Operational dashboard for RADIUS **server + client** traffic when metrics are
scraped as Prometheus series with the `eradius_` prefix (the
`eradius_prometheus_collector` path).

### What you can see

| Section | Insights |
|---------|----------|
| **Overview** | Request rate, auth accept ratio, reject/challenge ratio, pending work, client timeouts, protocol error rate |
| **Traffic & auth** | Access / accounting / CoA / disconnect mix; accept vs reject vs challenge; accounting start/stop/update; duplicates & retransmits |
| **Errors** | Malformed, bad authenticator, drops, unknown type, invalid NAS; client timeouts & retransmits |
| **Latency** | p50/p95/p99 for server handlers and client RTT; p95 by request type |
| **Per-NAS & upstream** | Top NAS by load; upstream `server_status`; per-NAS table (rate, accept ratio, rejects, bad auth, pending) |
| **Capacity** | Listener uptime / stats reset age |

### Variables

- **Datasource** — Prometheus (or compatible)
- **Server** — `server_name` label (`All` = `.*`)
- **NAS id** — `nas_id` label filtered by selected server(s)

### Prerequisites

1. Prometheus scraping your node (or PromEx endpoint if names match).
2. Erlang path:
   - `eradius` running with traffic
   - `eradius_prometheus_collector` started (attaches telemetry → histogram/boolean sink)
   - counters appear as `eradius_requests_total`, etc.
3. Optional: `{server_status_metrics_enabled, true}` for the **Upstream server status** panel (`server_status` metric).

### Import

1. Grafana → **Dashboards** → **New** → **Import**
2. Upload `eradius-overview.json` (or paste JSON)
3. Select your Prometheus datasource
4. Save

Or provision:

```yaml
# grafana provisioning example
apiVersion: 1
providers:
  - name: eradius
    type: file
    options:
      path: /var/lib/grafana/dashboards/eradius
```

Copy `eradius-overview.json` into that path.

### PromEx / Elixir naming

Default PromEx plugin prefix is `[:eradius]`, which usually produces the same
`eradius_*` counter names. If you set `metric_prefix: [:my_app, :eradius]`,
edit panel queries to use `my_app_eradius_*` (or add a second dashboard copy).

Histogram series need the `_bucket` / `_count` / `_sum` suffixes from the
Prometheus histogram (or TelemetryMetrics distribution export).

### Suggested alert rules (optional)

Sketch PromQL for Alertmanager — not wired in the JSON:

```promql
# High client timeout rate
sum(rate(eradius_client_timeouts_total[5m])) > 1

# Auth accept ratio collapse
sum(rate(eradius_accept_responses_total[5m]))
  / sum(rate(eradius_access_requests_total[5m])) < 0.5

# Handler backlog
sum(eradius_pending_requests_total) > 100

# Bad authenticators (secret mismatch / replay)
sum(rate(eradius_bad_authenticator_request_total[5m])) > 0.5
```

Tune thresholds to your traffic baseline.
