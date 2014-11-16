-module(erlmud).
-export([start/0, code_change/2]).

%% Startup
start() ->
    true = register(erlmud, spawn(fun() -> init() end)).

init() ->
    process_flag(trap_exit, true),
    note("Starting up."),
    Services = [{chanman, start_link, []},
                {charman, start_link, []},
                {accman, start_link, []},
                {wayman, start_link, []},
                {locman, start_link, []},
                {objman, start_link, []},
                {mobman, start_link, []},
                {netman, start_link, [{telnet, start_link, [2222]}]}],
    {ok, Running} = init(Services, []),
    loop(Running, Services).

init([], A) -> {ok, A};
init([{Module, Func, Args} | Rest], A) ->
    {ok, Pid} = apply(Module, Func, [self(), Args]),
    init(Rest, [{Pid, Module} | A]).

%% Service
loop(Running, Services) ->
  receive
    {From, Ref, {info, running}} ->
        From ! {Ref, Running},
        loop(Running, Services);
    {From, Ref, {info, services}} ->
        From ! {Ref, Services},
        loop(Running, Services);
    Message = {'EXIT', _, _} ->
        NewRunning = restart(Message, Running, Services),
        loop(NewRunning, Services);
    status ->
        note("Active components: ~tp", [Running]),
        loop(Running, Services);
    code_change ->
        ?MODULE:code_change(Running, Services);
    shutdown ->
        note("Shutting down."),
        shutdown(Running),
        exit(shutdown);
    Any ->
        note("Received ~tp", [Any]),
        loop(Running, Services)
  end.

shutdown(Running) ->
    note("Shutting down subordinates..."),
    Pids = live_pids(Running),
    em_lib:broadcast(Pids, shutdown),
    ok.

restart(Message = {'EXIT', Pid, Reason},
        Running,
        Services) ->
    case lists:keyfind(Pid, 1, Running) of
        Dead = {_, Name} ->
            note("Service ~p exited with ~p", [Name, Reason]),
            Dropped = lists:delete(Dead, Running),
            {M, F, A} = lists:keyfind(Name, 1, Services),
            {ok, NewPid} = apply(M, F, [self(), A]),
            [{NewPid, Name} | Dropped];
        false ->
            note("Received ~p", [Message]),
            {Running, Services}
    end.

%% Magic
live_pids(Running) ->
    [Pid || {Pid, _} <- Running].

%% Code changer
code_change(Running, Services) ->
    note("Changing code."),
    Pids = live_pids(Running),
    em_lib:broadcast(Pids, code_change),
    loop(Running, Services).

%% System
note(String) ->
    note(String, []).

note(String, Args) ->
    em_lib:note(?MODULE, String, Args).
