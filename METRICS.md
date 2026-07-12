# eradius metrics

`eradius` emits operational metrics through two complementary paths:

1. **Telemetry** (always on) — every counter/histogram/boolean update fires a
   `telemetry:execute/3` event. Core **never** dual-writes to `prometheus`.
2. **ETS counters** — counters are stored for pull/read aggregation
   (`eradius:statistics/1`, multi-node aggregator).

Optional scrapes:

* **Elixir / PromEx** — `prom_ex_eradius` plugin attaches to telemetry events.
* **Pure Erlang Prometheus** — start `eradius_prometheus_collector`, which
  attaches `eradius_prometheus_telemetry` (telemetry → prometheus histograms
  and booleans) and scrapes ETS counters via `prometheus_collector`.

## Telemetry event names

Stable event name prefixes under `[eradius | …]`:

| Event name | Fired by | Measurements | Metadata (typical keys) |
|------------|----------|--------------|-------------------------|
| `[eradius, inc_counter, Counter]` | `inc_counter/2` (NAS, client, server) | `#{}` | NAS: `server_name`, `server_ip`, `server_port`, `nas_ip`, `nas_id`; client: `client_name`, `client_ip`, `client_port`, `server_name`, `server_ip`, `server_port`; server: `server_name`, `server_ip`, `server_port` |
| `[eradius, dec_counter, Counter]` | `dec_counter/2` | `#{}` | same as inc |
| `[eradius, observe, Name]` | `observe/4`, `observe/5` | `#{value => Ms}` | client or NAS peer fields |
| `[eradius, boolean, Name]` | `set_boolean_metric/3` | `#{value => boolean()}` | `#{labels => Labels}` |

`Counter` is an atom such as `requests`, `accessAccepts`, `timeouts`,
`pending`, etc. `Name` is a prometheus-style metric atom such as
`eradius_request_duration_milliseconds` or `server_status`.

Example handler attachment:

```erlang
telemetry:attach(
    <<"my-handler">>,
    [eradius, inc_counter, requests],
    fun(_Event, Measurements, Metadata, _Config) ->
            io:format("requests ~p ~p~n", [Measurements, Metadata])
    end,
    undefined).
```

### Elixir PromEx plugin

For Elixir applications, use the optional `prom_ex_eradius` package in this
repository (`prom_ex_eradius/`). It implements `PromEx.Plugin` and maps the
events above to counters / distributions / last-value gauges. See
`prom_ex_eradius/README.md`.

### Grafana

A ready-made operational dashboard lives in
[`grafana/eradius-overview.json`](grafana/eradius-overview.json). Import into
Grafana (Prometheus datasource). See [`grafana/README.md`](grafana/README.md)
for panels, variables, and alert sketches.

## Prometheus scrapable metrics

For now, there are 2 groups of scrape metrics:

* `server` (metrics separated per nas and server names)
* `client`

`server` metrics are separated per nas and server names.

### The following `server` metrics exist:

_All metrics start with `eradius_` prefix and the prefix is not included into table to save space._

| Metric                                        | Labels                              | Type      |
| ----------------------------------------------|-------------------------------------|-----------|
| uptime_milliseconds                           | [$NAME, $IP, $PORT]                 | gauge     |
| since_last_reset_milliseconds                 | [$NAME, $IP, $PORT]                 | gauge     |
| requests_total                                | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| replies_total                                 | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| access_requests_total                         | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| accounting_requests_total                     | [$NAME, $IP, $PORT, $NASID, $NASIP, $TYPE] | counter   |
| coa_requests_total                            | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| disconnect_requests                           | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| accept_responses_total                        | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| reject_responses_total                        | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| access_challenge_responses_total              | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| accounting_responses_total                    | [$NAME, $IP, $PORT, $NASID, $NASIP, $TYPE] | counter   |
| coa_acks_total                                | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| coa_nacks_total                               | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| disconnect_acks_total                         | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| disconnect_nacks_total                        | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| malformed_requests_total                      | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| invalid_requests_total                        | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| retransmissions_total                         | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| duplicated_requests_total                     | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| pending_requests_total                        | [$NAME, $IP, $PORT, $NASID, $NASIP] | gauge     |
| unknown_type_request_total                    | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| bad_authenticator_request_total               | [$NAME, $IP, $PORT, $NASID, $NASIP] | counter   |
| request_duration_milliseconds                 | [$NAME, $IP, $PORT, $NASID, $NASIP] | histogram |
| access_request_duration_milliseconds          | [$NAME, $IP, $PORT, $NASID, $NASIP] | histogram |
| accounting_request_duration_milliseconds      | [$NAME, $IP, $PORT, $NASID, $NASIP] | histogram |
| coa_request_duration_milliseconds             | [$NAME, $IP, $PORT, $NASID, $NASIP] | histogram |
| disconnect_request_duration_milliseconds      | [$NAME, $IP, $PORT, $NASID, $NASIP] | histogram |

### The following `client` metrics exist:

_All metrics start with `eradius` prefix and the prefix is not included into table to save space._

| Metric                                             | Labels                                | Type      |
| ---------------------------------------------------|---------------------------------------| ----------|
|  client_requests_total                             | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_replies_total                              | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_access_requests_total                      | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_accounting_requests_total                  | [$NAME, $IP, $PORT, $CNAME, $CIP, $TYPE]     | counter   |
|  client_coa_requests_total                         | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_disconnect_requests_total                  | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_retransmissions_total                      | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_timeouts_total                             | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_accept_responses_total                     | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_access_challenge_responses_total           | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_reject_responses_total                     | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_accounting_responses_total                 | [$NAME, $IP, $PORT, $CNAME, $CIP, $TYPE]     | counter   |
|  client_coa_nacks_total                            | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_coa_acks_total                             | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_disconnect_acks_total                      | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_disconnect_nacks_total                     | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_packets_dropped_total                      | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_pending_requests_total                     | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_request_duration_milliseconds              | [$NAME, $IP, $PORT, $CNAME, $CIP]     | histogram |
|  client_reply_duration_milliseconds                | [$NAME, $IP, $PORT, $CNAME, $CIP]     | histogram |
|  client_access_request_duration_milliseconds       | [$NAME, $IP, $PORT, $CNAME, $CIP]     | histogram |
|  client_accounting_request_duration_milliseconds   | [$NAME, $IP, $PORT, $CNAME, $CIP]     | histogram |
|  client_coa_request_duration_milliseconds          | [$NAME, $IP, $PORT, $CNAME, $CIP]     | histogram |
|  client_disconnect_request_duration_milliseconds   | [$NAME, $IP, $PORT, $CNAME, $CIP]     | histogram |
|  client_unknown_type_request_total                 | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |
|  client_bad_authenticator_request_total            | [$NAME, $IP, $PORT, $CNAME, $CIP]     | counter   |

Besides these metrics RADIUS client also may create optional server status metrics which
could be enabled via `server_status_metrics_enabled` configuration option. These metrics
represent active/inactive state of upstream RADIUS servers that RADIUS clients
send requests to.

If RADIUS server status metrics are enabled following additional metric will be exposed:

| Metric                      | Labels              | Type    |
|-----------------------------|---------------------|---------|
| server_status               | [ $IP, $PORT ]      | boolean |


### Labels

Following prometheus labels are used to specify a metric:

`$NAME` - Server name. `$IP:$PORT` or name from configuration if exists. For this configuration:

    {servers, [
        {root, {"127.0.0.1", [1812, 1813]}}
    ]}

`root` will be used as a name.

`$IP` - server listener IP from configuration.

`$PORT` - server listener port from configuration.

`$NASID` - `ID_$NASID` or `nas_id` from configuration if exists.

`$NASIP` - NAS-IP-Address from configuration.

    {root, [
        { {"NAS1", [arg1, arg2]},
            [{"10.18.14.2", <<"secret1">>}]},
        { {"NAS2", [arg1, arg2]},
            [{{10, 18, 14, 3}, <<"secret2">>, [{nas_id, <<"name">>}]}]}
    ]}]

The configuration above describes two NASes fro one root RADIUS server.
For "NAS1" `$NASID` will be generated from ID an IP(`NAS1_10.18.14.2`), `$NASIP` = "10.18.14.2".
For "NAS2" `nas_id` will be used for `$NASID`(`name`)  `$NASIP` = "10.18.14.2".

`$CNAME` - name from `client_name` option fduring call `eradius_client:send_request/3` or `undefined` by default.

`$CIP` - `client_ip` from `eradius` enviroment.

`$TYPE` - accounting type, can be `start` | `stop` | `update`

All timing values in the histograms are in milliseconds.
