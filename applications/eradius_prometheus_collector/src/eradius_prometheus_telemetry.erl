%%%-------------------------------------------------------------------
%%% @doc Telemetry → prometheus sink for pure-Erlang scrapes.
%%%
%%% Core eradius emits only telemetry. This module attaches handlers that
%%% mirror observe/boolean events into prometheus.erl histograms/booleans
%%% so `eradius_prometheus_collector` histogram fetch and server_status
%%% continue to work when this app is started.
%%%-------------------------------------------------------------------
-module(eradius_prometheus_telemetry).

-export([attach/0, detach/0, handle_event/4]).

-define(HANDLER_ID, eradius_prometheus_telemetry).

-define(HISTOGRAM_EVENTS, [
    [eradius, observe, eradius_request_duration_milliseconds],
    [eradius, observe, eradius_access_request_duration_milliseconds],
    [eradius, observe, eradius_accounting_request_duration_milliseconds],
    [eradius, observe, eradius_coa_request_duration_milliseconds],
    [eradius, observe, eradius_disconnect_request_duration_milliseconds],
    [eradius, observe, eradius_client_request_duration_milliseconds],
    [eradius, observe, eradius_client_reply_duration_milliseconds],
    [eradius, observe, eradius_client_access_request_duration_milliseconds],
    [eradius, observe, eradius_client_accounting_request_duration_milliseconds],
    [eradius, observe, eradius_client_coa_request_duration_milliseconds],
    [eradius, observe, eradius_client_disconnect_request_duration_milliseconds]
]).

-define(BOOLEAN_EVENTS, [
    [eradius, boolean, server_status]
]).

-spec attach() -> ok | {error, term()}.
attach() ->
    case code:is_loaded(prometheus) of
        false ->
            {error, prometheus_not_loaded};
        {file, _} ->
            Events = ?HISTOGRAM_EVENTS ++ ?BOOLEAN_EVENTS,
            case telemetry:attach_many(?HANDLER_ID, Events, fun ?MODULE:handle_event/4, #{}) of
                ok -> ok;
                {error, already_exists} -> ok;
                Error -> Error
            end
    end.

-spec detach() -> ok.
detach() ->
    telemetry:detach(?HANDLER_ID).

%% @private
handle_event([eradius, observe, Name], #{value := Value}, Meta, _Config) ->
    observe_prometheus(Name, Value, Meta);
handle_event([eradius, boolean, Name], #{value := Value}, Meta, _Config) ->
    set_boolean_prometheus(Name, Value, Meta);
handle_event(_Event, _Meas, _Meta, _Config) ->
    ok.

observe_prometheus(Name, Value, Meta) ->
    {Labels, LabelNames, Help} = case maps:get(label_set, Meta, undefined) of
        nas ->
            ServerIP = maps:get(server_ip, Meta),
            ServerPort = maps:get(server_port, Meta),
            ServerName = maps:get(server_name, Meta),
            NasIP = maps:get(nas_ip, Meta),
            NasId = maps:get(nas_id, Meta),
            {[inet:ntoa(ServerIP), ServerPort, ServerName, inet:ntoa(NasIP), NasId],
             [server_ip, server_port, server_name, nas_ip, nas_id],
             maps:get(help, Meta, atom_to_list(Name))};
        _ ->
            %% client (default)
            ServerIP = maps:get(server_ip, Meta),
            ServerPort = maps:get(server_port, Meta),
            ServerName = maps:get(server_name, Meta),
            ClientName = maps:get(client_name, Meta, undefined),
            ClientIP = maps:get(client_ip, Meta, undefined),
            {[ServerIP, ServerPort, ServerName, ClientName, ClientIP],
             [server_ip, server_port, server_name, client_name, client_ip],
             maps:get(help, Meta, atom_to_list(Name))}
    end,
    try
        prometheus_histogram:observe(Name, Labels, Value)
    catch _:_ ->
        Buckets = application:get_env(eradius, histogram_buckets,
                                      [10, 30, 50, 75, 100, 1000, 2000]),
        prometheus_histogram:declare([{name, Name}, {labels, LabelNames},
                                      {duration_unit, milliseconds},
                                      {buckets, Buckets}, {help, Help}]),
        try prometheus_histogram:observe(Name, Labels, Value)
        catch _:_ -> ok
        end
    end,
    ok.

set_boolean_prometheus(Name, Value, Meta) ->
    Labels = maps:get(labels, Meta, []),
    try
        prometheus_boolean:set(Name, Labels, Value)
    catch _:_ ->
        prometheus_boolean:declare([{name, Name},
                                    {labels, [server_ip, server_port]},
                                    {help, "Status of an upstream RADIUS Server"}]),
        try prometheus_boolean:set(Name, Labels, Value)
        catch _:_ -> ok
        end
    end,
    ok.
