% Copyright (c) 2010-2017 by Travelping GmbH <info@travelping.com>

% Permission is hereby granted, free of charge, to any person obtaining a
% copy of this software and associated documentation files (the "Software"),
% to deal in the Software without restriction, including without limitation
% the rights to use, copy, modify, merge, publish, distribute, sublicense,
% and/or sell copies of the Software, and to permit persons to whom the
% Software is furnished to do so, subject to the following conditions:

% The above copyright notice and this permission notice shall be included in
% all copies or substantial portions of the Software.

% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
% DEALINGS IN THE SOFTWARE.

-module(eradius_client_SUITE).
-compile(export_all).

-include("test/eradius_test.hrl").
-include_lib("eradius/include/eradius_lib.hrl").

-define(BAD_SERVER_IP, {eradius_test_handler:localhost(ip), 1820, "secret"}).
-define(BAD_SERVER_INITIAL_RETRIES, 3).
-define(BAD_SERVER_TUPLE_INITIAL, {{eradius_test_handler:localhost(tuple), 1820},
                                   ?BAD_SERVER_INITIAL_RETRIES,
                                   ?BAD_SERVER_INITIAL_RETRIES}).
-define(BAD_SERVER_TUPLE, {{eradius_test_handler:localhost(tuple), 1820},
                           ?BAD_SERVER_INITIAL_RETRIES - 1,
                           ?BAD_SERVER_INITIAL_RETRIES}).
-define(BAD_SERVER_IP_ETS_KEY, {eradius_test_handler:localhost(tuple), 1820}).

-define(GOOD_SERVER_INITIAL_RETRIES, 3).
-define(GOOD_SERVER_TUPLE, {{eradius_test_handler:localhost(tuple), 1812},
                            ?GOOD_SERVER_INITIAL_RETRIES,
                            ?GOOD_SERVER_INITIAL_RETRIES}).
-define(GOOD_SERVER_2_TUPLE, {{{127, 0, 0, 2}, 1813},
                              ?GOOD_SERVER_INITIAL_RETRIES,
                              ?GOOD_SERVER_INITIAL_RETRIES}).

-define(RADIUS_SERVERS, [?GOOD_SERVER_TUPLE,
                         ?BAD_SERVER_TUPLE_INITIAL,
                         ?GOOD_SERVER_2_TUPLE]).

all() -> [
    send_request,
    wanna_send,
    reconf_address,
    wanna_send,
    reconf_ports_30,
    wanna_send,
    reconf_ports_10,
    wanna_send,
    send_request_failover,
    failover_preserves_route_options,
    failover_tracks_final_peer_failure,
    failover_peer_options_override_route_options,
    failover_peer_overrides_do_not_leak,
    failover_supports_hostname_peer,
    failover_returns_no_active_servers,
    check_upstream_servers
  ].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(eradius),
    startSocketCounter(),
    Config.

end_per_suite(_Config) ->
    stopSocketCounter(),
    application:stop(eradius),
    ok.

init_per_testcase(TestCase, Config) ->
    case uses_test_handler(TestCase) of
        true ->
            application:stop(eradius),
            eradius_test_handler:start();
        false ->
            ok
    end,
    Config.

end_per_testcase(TestCase, Config) ->
    case uses_test_handler(TestCase) of
        true -> eradius_test_handler:stop();
        false -> ok
    end,
    Config.

uses_test_handler(TestCase) ->
    lists:member(TestCase, [send_request, send_request_failover,
                            failover_preserves_route_options,
                            failover_tracks_final_peer_failure,
                            failover_peer_options_override_route_options,
                            failover_peer_overrides_do_not_leak,
                            failover_supports_hostname_peer,
                            failover_returns_no_active_servers,
                            check_upstream_servers]).

%% STUFF

socketCounter(Count) ->
    receive
        add         -> socketCounter(Count+1);
        del         -> socketCounter(Count-1);
        {get, PID}  -> PID ! {ok, Count}, socketCounter(Count);
        stop        -> done
    end.

startSocketCounter() ->
    register(socketCounter, spawn(?MODULE, socketCounter, [0])).

stopSocketCounter() ->
    socketCounter ! stop,
    unregister(socketCounter).

addSocket() -> socketCounter ! add.
delSocket() -> socketCounter ! del.

getSocketCount() ->
    socketCounter ! {get, self()},
    receive
        {ok, Count} -> Count
    end.

testSocket(undefined) -> true;
testSocket(Pid) ->
    Pid ! {status, self()},
    receive
        {ok, active}    -> false;
        {ok, inactive}  -> true
    after
        50 -> true
    end.

-record(state, {
    socket_ip :: inet:ip_address(),
    no_ports = 1 :: pos_integer(),
    idcounters = maps:new() :: map(),
    sockets = array:new() :: array:array(),
    sup :: pid(),
    subscribed_clients = [] :: [{{integer(),integer(),integer(),integer()}, integer()}]
}).

split(N, List) -> split2(N, [], List).

split2(0, List1, List2)     -> {lists:reverse(List1), List2};
split2(_, List1, [])        -> {lists:reverse(List1), []};
split2(N, List1, [L|List2]) -> split2(N-1, [L|List1], List2).

meckStart() ->
    ok = meck:new(eradius_client_socket),
    ok = meck:expect(eradius_client_socket, start, fun(X, Y, Z) -> eradius_client_socket_test:start(X, Y, Z) end),
    ok = meck:expect(eradius_client_socket, init, fun(X) -> eradius_client_socket_test:init(X) end),
    ok = meck:expect(eradius_client_socket, handle_call, fun(X, Y, Z) -> eradius_client_socket_test:handle_call(X, Y, Z) end),
    ok = meck:expect(eradius_client_socket, handle_cast, fun(X, Y) -> eradius_client_socket_test:handle_cast(X, Y) end),
    ok = meck:expect(eradius_client_socket, handle_info, fun(X, Y) -> eradius_client_socket_test:handle_info(X, Y) end),
    ok = meck:expect(eradius_client_socket, terminate, fun(X, Y) -> eradius_client_socket_test:terminate(X, Y) end),
    ok = meck:expect(eradius_client_socket, code_change, fun(X, Y, Z) -> eradius_client_socket_test:code_change(X, Y, Z) end).

meckStop() ->
    ok = meck:unload(eradius_client_socket).

parse_ip(undefined) ->
    {ok, undefined};
parse_ip(Address) when is_list(Address) ->
    inet_parse:address(Address);
parse_ip(T = {_, _, _, _}) ->
    {ok, T};
parse_ip(T = {_, _, _, _, _, _}) ->
    {ok, T}.

%% CHECK

test(true, _Msg) -> true;
test(false, Msg) ->
    io:format(standard_error, "~s~n", [Msg]),
    false.

check(OldState, NewState = #state{no_ports = P}, null, A) -> check(OldState, NewState, P, A);
check(OldState, NewState = #state{socket_ip = A}, P, null) -> check(OldState, NewState, P, A);
check(#state{sockets = OS, no_ports = _OP, idcounters = _OC, socket_ip = OA},
        #state{sockets = NS, no_ports = NP, idcounters = NC, socket_ip = NA},
        P, A) ->
    {ok, PA} = parse_ip(A),
    test(PA == NA, "Adress not configured") and
    case NA of
        OA  ->
            {_, Rest} = split(NP, array:to_list(OS)),
            test(P == NP,"Ports not configured") and
            test(maps:fold( fun(_Peer, {NextPortIdx, _NextReqId}, Akk) ->
                                    Akk and (NextPortIdx =< NP)
                            end, true, NC), "Invalid port counter") and
            test(getSocketCount() =< NP, "Sockets not closed") and
            test(array:size(NS) =< NP, "Socket array not resized") and
            test(lists:all(fun(Pid) -> testSocket(Pid) end, Rest), "Sockets still available");
        _   ->
            test(array:size(NS) == 0, "Socket array not cleaned") and
            test(getSocketCount() == 0, "Sockets not closed") and
            test(lists:all(fun(Pid) -> testSocket(Pid) end, array:to_list(OS)), "Sockets still available")
    end.

%% TESTS

send_request(_Config) ->
    ?equal(accept, eradius_test_handler:send_request(eradius_test_handler:localhost(tuple))),
    ?equal(accept, eradius_test_handler:send_request(eradius_test_handler:localhost(ip))),
    ?equal(accept, eradius_test_handler:send_request(eradius_test_handler:localhost(string))),
    ?equal(accept, eradius_test_handler:send_request(eradius_test_handler:localhost(binary))),
    ok.

send(FUN, Ports, Address) ->
    meckStart(),
    {ok, OldState} = gen_server:call(eradius_client, debug),
    FUN(),
    {ok, NewState} = gen_server:call(eradius_client, debug),
    true = check(OldState, NewState, Ports, Address),
    meckStop().

wanna_send(_Config) ->
    lists:map(fun(_) ->
                        IP = {rand:uniform(100), rand:uniform(100), rand:uniform(100), rand:uniform(100)},
                        Port = rand:uniform(100),
                        MetricsInfo = {{undefined, undefined, undefined}, {undefined, undefined, undefined}},
                        FUN = fun() -> gen_server:call(eradius_client, {wanna_send, {undefined, {IP, Port}}, MetricsInfo}) end,
                        send(FUN, null, null)
                end, lists:seq(1, 10)).

%% I've catched some data races with `delSocket()' and `getSocketCount()' when
%% `delSocket()' happens after `getSocketCount()' (because `delSocket()' is sent from another process).
%% I don't know a better decision than add some delay before `getSocketCount()'
reconf_address(_Config) ->
    FUN = fun() -> gen_server:call(eradius_client, reconfigure), timer:sleep(100) end,
    application:set_env(eradius, client_ip, "7.13.23.42"),
    send(FUN, null, "7.13.23.42").

reconf_ports_30(_Config) ->
    FUN = fun() -> gen_server:call(eradius_client, reconfigure), timer:sleep(100) end,
    application:set_env(eradius, client_ports, 30),
    send(FUN, 30, null).

reconf_ports_10(_Config) ->
    FUN = fun() -> gen_server:call(eradius_client, reconfigure), timer:sleep(100) end,
    application:set_env(eradius, client_ports, 10),
    send(FUN, 10, null).

send_request_failover(_Config) ->
    ?equal(accept, eradius_test_handler:send_request_failover(?BAD_SERVER_IP)),
    {ok, Timeout} = application:get_env(eradius, unreachable_timeout),
    timer:sleep(Timeout * 1000),
    ?equal([?BAD_SERVER_TUPLE], ets:lookup(eradius_client, ?BAD_SERVER_IP_ETS_KEY)),
    ok.

failover_preserves_route_options(_Config) ->
    ct:timetrap({seconds, 1}),
    IP = eradius_test_handler:localhost(tuple),
    FinalPeer = {IP, 1821, "secret"},
    eradius_client:store_radius_server_from_pool(IP, 1821, 3),
    Options = [{retries, 1}, {timeout, 10}, {failover, [FinalPeer]}],
    {{error, timeout}, Duration} = timed_request(?BAD_SERVER_IP, Options),
    ?equal(true, Duration < 500),
    ok.

failover_tracks_final_peer_failure(_Config) ->
    IP = eradius_test_handler:localhost(tuple),
    FinalPort = 1821,
    application:set_env(eradius, unreachable_timeout, 1),
    FinalPeer = {IP, FinalPort, "secret"},
    eradius_client:store_radius_server_from_pool(IP, FinalPort, 1),
    Options = [{retries, 1}, {timeout, 10}, {failover, [FinalPeer]}],
    ?equal({error, timeout},
           eradius_client:send_request(?BAD_SERVER_IP,
                                       #radius_request{cmd = request}, Options)),
    ?equal([], ets:lookup(eradius_client, {IP, FinalPort})),
    ?equal([{{IP, FinalPort}, 1, 1}],
           wait_for_upstream_server({IP, FinalPort}, 1500)),
    ok.

failover_peer_options_override_route_options(_Config) ->
    IP = eradius_test_handler:localhost(tuple),
    FinalPort = 1821,
    ets:delete(eradius_client, ?BAD_SERVER_IP_ETS_KEY),
    eradius_client:store_radius_server_from_pool(IP, FinalPort, 2),
    PeerOptions = [{retries, 1}, {timeout, 10}, {server_name, peer_server}],
    FinalPeer = {IP, FinalPort, "secret", PeerOptions},
    RouteOptions = [{retries, 3}, {timeout, 1000}, {server_name, route_server},
                    {client_name, route_client}, {failover, [FinalPeer]}],
    HandlerId = {?MODULE, failover_peer_options, make_ref()},
    ok = telemetry:attach(HandlerId, [eradius, inc_counter, requests],
                          fun (_Event, _Measurements, Metadata, TestPid) ->
                              TestPid ! {request_metadata, Metadata}
                          end, self()),
    try
        {{error, timeout}, Duration} = timed_request(?BAD_SERVER_IP, RouteOptions),
        ?equal(true, Duration < 500),
        Metadata = receive_request_metadata(),
        ?match(#{server_name := peer_server, client_name := route_client}, Metadata)
    after
        telemetry:detach(HandlerId)
    end,
    ok.

failover_peer_overrides_do_not_leak(_Config) ->
    IP = eradius_test_handler:localhost(tuple),
    ets:delete(eradius_client, ?BAD_SERVER_IP_ETS_KEY),
    eradius_client:store_radius_server_from_pool(IP, 1821, 2),
    FirstPeerOptions = [{retries, 1}, {timeout, 10}, {server_name, first_peer}],
    FirstPeer = {IP, 1821, "secret", FirstPeerOptions},
    SecondPeer = {IP, 1812, "secret"},
    RouteOptions = [{retries, 1}, {timeout, 100}, {server_name, route_server},
                    {client_name, route_client}, {failover, [FirstPeer, SecondPeer]}],
    HandlerId = {?MODULE, failover_peer_override_leak, make_ref()},
    ok = telemetry:attach(HandlerId, [eradius, inc_counter, requests],
                          fun (_Event, _Measurements, Metadata, TestPid) ->
                              TestPid ! {request_metadata, Metadata}
                          end, self()),
    try
        {ok, Response, Authenticator} =
            eradius_client:send_request(?BAD_SERVER_IP,
                                        #radius_request{cmd = request}, RouteOptions),
        #radius_request{cmd = accept} =
            eradius_lib:decode_request(Response, <<"secret">>, Authenticator),
        FirstMetadata = receive_request_metadata(),
        SecondMetadata = receive_request_metadata(),
        ?match(#{server_name := first_peer, client_name := route_client}, FirstMetadata),
        ?match(#{server_name := route_server, client_name := route_client}, SecondMetadata)
    after
        telemetry:detach(HandlerId)
    end,
    ok.

failover_supports_hostname_peer(_Config) ->
    ets:delete(eradius_client, ?BAD_SERVER_IP_ETS_KEY),
    HostnamePeer = {eradius_test_handler:localhost(string), 1812, "secret"},
    Options = [{retries, 1}, {timeout, 10}, {failover, [HostnamePeer]}],
    {ok, Response, Authenticator} =
        eradius_client:send_request(?BAD_SERVER_IP,
                                    #radius_request{cmd = request}, Options),
    #radius_request{cmd = accept} =
        eradius_lib:decode_request(Response, <<"secret">>, Authenticator),
    ok.

failover_returns_no_active_servers(_Config) ->
    IP = eradius_test_handler:localhost(tuple),
    Options = [{failover, [{IP, 1823, "secret"}]}],
    ?equal(no_active_servers,
           eradius_client:send_request({IP, 1822, "secret"},
                                       #radius_request{cmd = request}, Options)),
    ok.

receive_request_metadata() ->
    receive
        {request_metadata, Metadata} ->
            Metadata
    after
        1000 ->
            ct:fail(request_metadata_timeout)
    end.

wait_for_upstream_server(Key, Timeout) ->
    wait_for_upstream_server(Key, Timeout, erlang:monotonic_time(millisecond)).

wait_for_upstream_server(Key, Timeout, Start) ->
    case ets:lookup(eradius_client, Key) of
        [] ->
            case erlang:monotonic_time(millisecond) - Start >= Timeout of
                true -> [];
                false ->
                    timer:sleep(10),
                    wait_for_upstream_server(Key, Timeout, Start)
            end;
        Server ->
            Server
    end.

timed_request(Server, Options) ->
    Start = erlang:monotonic_time(millisecond),
    Result = eradius_client:send_request(Server, #radius_request{cmd = request}, Options),
    {Result, erlang:monotonic_time(millisecond) - Start}.

check_upstream_servers(_Config) ->
    ?equal(?RADIUS_SERVERS, ets:tab2list(eradius_client)),
    ok.
