-module(eradius_prometheus_collector_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    _ = application:ensure_all_started(prometheus),
    _ = eradius_prometheus_telemetry:attach(),
    eradius_prometheus_collector_sup:start_link().

stop(_State) ->
    eradius_prometheus_telemetry:detach(),
    ok.
