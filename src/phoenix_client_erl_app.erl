%%%-------------------------------------------------------------------
%% @doc phoenix_client_erl public API
%% @end
%%%-------------------------------------------------------------------

-module(phoenix_client_erl_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    phoenix_client_erl_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================