# PromExEradius

Optional [PromEx](https://github.com/akoutmos/prom_ex) plugin for
[eradius](https://github.com/Flickswitch/eradius).

It attaches to eradius **telemetry** events and exposes counters, histograms,
and status gauges for Prometheus scrape via your host app's PromEx endpoint.

Core `eradius` does **not** require this package. Pure Erlang releases can keep
using `eradius_prometheus_collector` (or any other telemetry handler).

## Requirements

- Elixir 1.15+
- A host application that already runs PromEx
- `eradius` started in the same BEAM (emits `[:eradius | …]` events)

## Install

In your Elixir app's `mix.exs`:

```elixir
defp deps do
  [
    {:eradius, "~> 2.0"},           # or path/git
    {:prom_ex, "~> 1.9"},
    {:prom_ex_eradius, path: "path/to/eradius/prom_ex_eradius"}
    # later: {:prom_ex_eradius, "~> 0.1"}
  ]
end
```

## Usage

```elixir
defmodule MyApp.PromEx do
  use PromEx, otp_app: :my_app

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      # All defaults:
      PromExEradius,
      # Or with options:
      {PromExEradius,
       metric_prefix: [:my_app, :eradius],
       duration_buckets: [10, 30, 50, 75, 100, 250, 500, 1000, 2000, 5000]}
    ]
  end

  @impl true
  def dashboards, do: []
end
```

Ensure `:eradius` is in your release applications list (or started before traffic).

## Telemetry events (from eradius)

| Event | PromEx mapping |
|-------|----------------|
| `[:eradius, :inc_counter, counter]` | Counter `…_total` (one metric group per known counter) |
| `[:eradius, :dec_counter, :pending]` | Counter of decrements (pair with pending incs for net) |
| `[:eradius, :observe, name]` | Distribution (duration histograms, native→ms) |
| `[:eradius, :boolean, :server_status]` | Last-value gauge (0/1) |

Stable event contract is documented in eradius `METRICS.md`.

## Labels

Tag set depends on the event side (NAS vs client vs server):

- Common: `server_name`, `server_ip`, `server_port`
- NAS: `nas_ip`, `nas_id`
- Client: `client_name`, `client_ip`, `client_port`
- Boolean: labels from the event metadata (`labels` list is stringified)

IPs and non-string tags are converted to strings for Prometheus.

## License

MIT (same as eradius).
