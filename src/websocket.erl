-module(websocket).

-behaviour(transport).
-behaviour(websocket_client_handler).

%% api
-export([
	open/2,
	close/1,
	init/2,
	onconnect/2,
	ondisconnect/2,
	websocket_handle/3,
	websocket_info/3,
	websocket_terminate/3
]).

open(Url, TransportOpts) ->
	websocket_client:start_link(
      erlang:binary_to_list(Url),
      ?MODULE,
      TransportOpts,
      TransportOpts).

close(Socket) ->
	erlang:send(Socket, close).


init(Opts, _Req) ->
    % {once, #{opts => Opts, 
  		% 	sender => maps:get(sender, Opts)}
    % }.
	{ok, #{opts => Opts, 
  			sender => proplists:get_value(sender, Opts)}}.

onconnect(_, #{sender := Sender} = State) ->
	erlang:send(Sender, {connected, self()}),
	{ok, State}.

ondisconnect(Reason, #{sender := Sender} = State) ->
	erlang:send(Sender, {disconnected, Reason, self()}),
	{close, normal, State}.

% Receives JSON encoded Socket.Message from remote WS endpoint and
% forwards message to client sender process
websocket_handle({text, Msg}, _ConnState, #{sender := Sender} = State) ->
	erlang:send(Sender, {'receive', Msg}),
	{ok, State};

websocket_handle(_OtherMsg, _Req, State) ->
	{ok, State}.

websocket_info({send, Msg}, _ConnState, State) ->
	{reply, {text, Msg}, State};

websocket_info(close, _ConnState, #{sender := Sender} = _State) ->
	erlang:send(Sender, {closed, normal, self()}),
	{close, <<>>, <<"done">>};

websocket_info(_Message, _Req, State) ->
	{ok, State}.

websocket_terminate(_Reason, _ConnState, _State) ->
	ok.



