%%%-------------------------------------------------------------------
%%% @doc Common Test suite: verify shipped metric paths emit telemetry.
%%% Drives eradius_counter API (inc/dec/observe/boolean) with a temporary
%%% telemetry handler — no reimplementation of the unit under test.
%%%-------------------------------------------------------------------
-module(eradius_telemetry_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("eradius/include/eradius_lib.hrl").

-define(HANDLER_ID, eradius_telemetry_SUITE_handler).
-define(ETS, eradius_telemetry_SUITE_events).

all() ->
    [client_inc_emits_telemetry,
     client_dec_emits_telemetry,
     nas_inc_emits_telemetry,
     nas_dec_emits_telemetry,
     server_inc_emits_telemetry,
     observe_client_emits_telemetry,
     observe_nas_emits_telemetry,
     boolean_emits_telemetry].

init_per_suite(Config) ->
    application:load(eradius),
    application:set_env(eradius, servers, []),
    application:set_env(eradius, session_nodes, local),
    application:set_env(eradius, tables, [dictionary]),
    application:set_env(eradius, logging, false),
    application:set_env(eradius, client_ip, undefined),
    application:set_env(eradius, client_ports, 10),
    application:set_env(eradius, counter_aggregator, false),
    application:set_env(eradius, server_status_metrics_enabled, false),
    {ok, _} = application:ensure_all_started(eradius),
    Config.

end_per_suite(_Config) ->
    application:stop(eradius),
    ok.

init_per_testcase(_TestCase, Config) ->
    ets:new(?ETS, [named_table, public, bag]),
    ok = telemetry:attach_many(
           ?HANDLER_ID,
           [[eradius, inc_counter, requests],
            [eradius, inc_counter, pending],
            [eradius, inc_counter, invalidRequests],
            [eradius, dec_counter, pending],
            [eradius, observe, eradius_test_hist],
            [eradius, boolean, server_status]],
           fun handler/4,
           #{}),
    Config.

end_per_testcase(_TestCase, _Config) ->
    telemetry:detach(?HANDLER_ID),
    case ets:info(?ETS) of
        undefined -> ok;
        _ -> ets:delete(?ETS)
    end,
    ok.

%% -- handler stores every event for assertions -------------------------
handler(Event, Measurements, Metadata, _Config) ->
    ets:insert(?ETS, {Event, Measurements, Metadata}),
    ok.

wait_for_event(Event, TimeoutMs) ->
    wait_for_event(Event, TimeoutMs, erlang:monotonic_time(millisecond)).

wait_for_event(Event, TimeoutMs, Start) ->
    case ets:lookup(?ETS, Event) of
        [] ->
            case erlang:monotonic_time(millisecond) - Start > TimeoutMs of
                true -> {error, {timeout, Event}};
                false ->
                    timer:sleep(10),
                    wait_for_event(Event, TimeoutMs, Start)
            end;
        Matches ->
            {ok, Matches}
    end.

client_key() ->
    {{test_client, {127, 0, 0, 2}, undefined},
     {upstream, {10, 0, 0, 1}, 1812}}.

nas_prop() ->
    #nas_prop{
       server_ip = {127, 0, 0, 1},
       server_port = 1812,
       nas_ip = {127, 0, 0, 2},
       nas_id = <<"nas1">>,
       metrics_info = {{test_server, '127.0.0.1', '1812'},
                       {nas1, '127.0.0.2', undefined}},
       secret = <<"secret">>,
       handler_nodes = local
      }.

%% -- tests -------------------------------------------------------------
client_inc_emits_telemetry(_Config) ->
    Key = client_key(),
    eradius_counter:inc_counter(requests, Key),
    {ok, [{Event, Meas, Meta} | _]} =
        wait_for_event([eradius, inc_counter, requests], 1000),
    ?assertEqual([eradius, inc_counter, requests], Event),
    ?assertEqual(#{}, Meas),
    ?assertMatch(#{client_name := test_client,
                   server_name := upstream,
                   server_port := 1812}, Meta),
    ok.

client_dec_emits_telemetry(_Config) ->
    Key = client_key(),
    eradius_counter:dec_counter(pending, Key),
    {ok, [{Event, _Meas, Meta} | _]} =
        wait_for_event([eradius, dec_counter, pending], 1000),
    ?assertEqual([eradius, dec_counter, pending], Event),
    ?assertMatch(#{client_name := test_client, server_ip := {10, 0, 0, 1}}, Meta),
    ok.

nas_inc_emits_telemetry(_Config) ->
    Nas = nas_prop(),
    eradius_counter:inc_counter(requests, Nas),
    {ok, [{Event, _Meas, Meta} | _]} =
        wait_for_event([eradius, inc_counter, requests], 1000),
    ?assertEqual([eradius, inc_counter, requests], Event),
    ?assertMatch(#{server_name := test_server,
                   server_ip := {127, 0, 0, 1},
                   server_port := 1812,
                   nas_ip := {127, 0, 0, 2},
                   nas_id := <<"nas1">>}, Meta),
    ok.

nas_dec_emits_telemetry(_Config) ->
    Nas = nas_prop(),
    eradius_counter:dec_counter(pending, Nas),
    {ok, [{Event, _Meas, Meta} | _]} =
        wait_for_event([eradius, dec_counter, pending], 1000),
    ?assertEqual([eradius, dec_counter, pending], Event),
    ?assertMatch(#{nas_id := <<"nas1">>, server_port := 1812}, Meta),
    ok.

server_inc_emits_telemetry(_Config) ->
    C0 = eradius_counter:init_counter({{127, 0, 0, 1}, 1812, test_srv}),
    C1 = eradius_counter:inc_counter(invalidRequests, C0),
    ?assertEqual(1, C1#server_counter.invalidRequests),
    {ok, [{Event, _Meas, Meta} | _]} =
        wait_for_event([eradius, inc_counter, invalidRequests], 1000),
    ?assertEqual([eradius, inc_counter, invalidRequests], Event),
    ?assertMatch(#{server_name := test_srv,
                   server_ip := {127, 0, 0, 1},
                   server_port := 1812}, Meta),
    ok.

observe_client_emits_telemetry(_Config) ->
    Key = client_key(),
    eradius_counter:observe(eradius_test_hist, Key, 42.5, "test histogram"),
    {ok, [{Event, Meas, Meta} | _]} =
        wait_for_event([eradius, observe, eradius_test_hist], 1000),
    ?assertEqual([eradius, observe, eradius_test_hist], Event),
    ?assertMatch(#{value := 42.5}, Meas),
    ?assertMatch(#{server_name := upstream, client_name := test_client}, Meta),
    ok.

observe_nas_emits_telemetry(_Config) ->
    Nas = nas_prop(),
    eradius_counter:observe(eradius_test_hist, Nas, 12.0, test_server, "nas hist"),
    {ok, [{Event, Meas, Meta} | _]} =
        wait_for_event([eradius, observe, eradius_test_hist], 1000),
    ?assertEqual([eradius, observe, eradius_test_hist], Event),
    ?assertMatch(#{value := 12.0}, Meas),
    ?assertMatch(#{server_name := test_server, nas_id := <<"nas1">>}, Meta),
    ok.

boolean_emits_telemetry(_Config) ->
    eradius_counter:set_boolean_metric(server_status, [{10, 0, 0, 1}, 1812], true),
    {ok, [{Event, Meas, Meta} | _]} =
        wait_for_event([eradius, boolean, server_status], 1000),
    ?assertEqual([eradius, boolean, server_status], Event),
    ?assertMatch(#{value := true}, Meas),
    ?assertMatch(#{labels := [{10, 0, 0, 1}, 1812]}, Meta),
    ok.
