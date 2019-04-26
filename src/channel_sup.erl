-module(channel_sup).

-behaviour(supervisor).

%% API
-export([
    start_link/0,
    start_link/1,
	start_channel/3
]).

%% Supervisor callbacks
-export([
    init/1
]).

%%====================================================================
%% API functions
%%====================================================================
start_channel(Socket, Topic, Params) ->
    Spec = channel:child_spec({Socket, Topic, Params}),
    supervisor:start_child(?MODULE, Spec).

%%====================================================================
%% Supervisor callbacks
%%====================================================================
start_link() ->
    start_link([]).
    
start_link(Opts) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Opts]).

init(_Opts) ->
    {ok, {{one_for_one, 10, 1}, []}}.


%%====================================================================
%% Internal functions
%%====================================================================
