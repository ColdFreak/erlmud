-module(charman).
-export([start/1, start/2, start_link/1, start_link/2, code_change/1,
         save/1, list/1, load/2, check/1, make/2, drop/2]).

%% Interface
save(Char) -> call(save, Char).

list(Acc) -> call(get_chars, Acc).

load(Acc, Name) -> call(load_char, {Acc, Name}).

check(Name) -> call(check_char, Name).

make(Acc, Char) -> call(make_char, {Acc, Char}).

drop(Acc, Name) -> call(drop_char, {Acc, Name}).

call(Verb, Data) -> call({Verb, Data}).
call(Request) -> em_lib:call(?MODULE, Request).

%% Startup
start(Parent)            -> start(Parent, []).
start(Parent, Conf)      -> starter(fun spawn/1, Parent, Conf).
start_link(Parent)       -> start_link(Parent, []).
start_link(Parent, Conf) -> starter(fun spawn_link/1, Parent, Conf).

starter(Spawn, Parent, Conf) ->
    Name = ?MODULE,
    case whereis(Name) of
        undefined ->
            Pid = Spawn(fun() -> init(Parent, Conf) end),
            true = register(Name, Pid),
            {ok, Pid};
        Pid ->
            {ok, Pid}
    end.

init(Parent, Conf) ->
    note("Initializing with ~p.", [Conf]),
    Accs = load_accounts(),
    Chars = load_characters(),
    loop({Parent, Conf, Accs, Chars}).

load_accounts() -> dict:new().

load_characters() -> dict:new().

%% Service
loop(State = {Parent, Conf, Accs, Chars}) ->
  receive
    {From, Ref, {save, Char}} ->
        NewChars = remember(Char, Chars),
        From ! {Ref, ok},
        loop({Parent, Conf, Accs, NewChars});
    {From, Ref, {get_chars, Acc}} ->
        Result = get_chars(Acc, Accs),
        From ! {Ref, Result},
        loop(State);
    {From, Ref, {load_char, {Acc, Name}}} ->
        Result = load_char(Accs, Chars, Acc, Name),
        From ! {Ref, Result},
        loop(State);
    {From, Ref, {check_char, Name}} ->
        From ! {Ref, check_char(Chars, Name)},
        loop(State);
    {From, Ref, {make_char, {Acc, Char}}} ->
        {Result, NewState} = make_char(State, Acc, Char),
        From ! {Ref, Result},
        loop(NewState);
    {From, Ref, {drop_char, {Acc, Name}}} ->
        {Result, NewState} = drop_char(State, Acc, Name),
        From ! {Ref, Result},
        loop(NewState);
    {'EXIT', Parent, Reason} ->
        note("Parent~tp died with ~tp~nFollowing my leige!~n...Blarg!", [Parent, Reason]);
    status ->
        note("Status:~n  Conf: ~p~n  Accs: ~p~n  Chars: ~p~n",
             [Conf, dict:to_list(Accs), dict:to_list(Chars)]),
        loop(State);
    code_change ->
        ?MODULE:code_change(State);
    shutdown ->
        note("Shutting down."),
        exit(shutdown);
    Any ->
        note("Received ~tp", [Any]),
        loop(State)
  end.

%% Registry functions
remember({Name, Data}, Chars) ->
    dict:store(Name, Data, Chars).

get_chars(Acc, Accs) ->
    case dict:find(Acc, Accs) of
        {ok, Result} -> Result;
        error        -> []
    end.

load_char(Accs, Chars, Acc, Name) ->
    case dict:find(Acc, Accs) of
        {ok, List} ->
            case lists:member(Name, List) of
                true  -> {ok, dict:fetch(Name, Chars)};
                false -> {error, owner}
            end;
        error ->
            {error, owner}
    end.

check_char(Chars, Name) ->
    case dict:is_key(Name, Chars) of
        false -> available;
        true  -> taken
    end.

make_char(State, Acc, {Name,  Data = none}) ->
    new_char(State, Acc, Name, Data);
make_char(State, Acc, Data = {{Mod, _}, _}) ->
    Name = Mod:read(name, Data),
    new_char(State, Acc, Name, Data).

new_char(State = {Parent, Conf, Accs, Chars}, Acc, Name, Data) ->
    case dict:is_key(Name, Chars) of
        true  ->
            {{error, exists}, State};
        false ->
            NewAccs = dict:append(Acc, Name, Accs),
            NewChars = dict:store(Name, Data, Chars),
            {ok, {Parent, Conf, NewAccs, NewChars}}
    end.

drop_char(State = {Parent, Conf, Accs, Chars}, Acc, Name) ->
    case dict:find(Acc, Accs) of
        {ok, List} ->
            case lists:member(Name, List) of
                true ->
                    NewAccs = dict:store(Acc, lists:delete(Name, List), Accs),
                    NewChars = dict:erase(Name, Chars),
                    {ok, {Parent, Conf, NewAccs, NewChars}};
                false ->
                    Response = {error, owner},
                    {Response, State}
            end;
        false ->
            Response = {error, owner},
            {Response, State}
    end.

%% Code changer
code_change(State) ->
    note("Changing code."),
    loop(State).

%% System
note(String) ->
    note(String, []).

note(String, Args) ->
    em_lib:note(?MODULE, String, Args).
