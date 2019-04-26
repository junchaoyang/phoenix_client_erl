%%%-------------------------------------------------------------------
%% @doc phoenix_client_erl top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(phoenix_client_erl_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SHUTDOWN_TIMEOUT, 15).
%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    {ok, {{one_for_one, 10, 1},
    [
     supervisor(channel_sup)
     % worker(example)
     ]}}.
%%%===================================================================
%%% Internal functions
%%%===================================================================
worker(Mod) ->
    {Mod, {Mod, start_link, []}, permanent, ?SHUTDOWN_TIMEOUT, worker, [Mod]}.

supervisor(Mod) ->
    supervisor(Mod, Mod).

supervisor(Name, Mod) ->
    {Name, {Mod, start_link, []}, permanent, infinity, supervisor, [Mod]}.

