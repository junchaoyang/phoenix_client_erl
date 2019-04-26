-module(example).

-behaviour(gen_server).

%% gen_server callback
-export([
    init/1, 
    handle_call/3, 
    handle_cast/2,
    handle_info/2, 
    terminate/2,
    code_change/3
]).

-export([
	start_link/0,
	push/2,
	test/0
]).

%% test 
test() ->
	push(ping, jiffy:encode(#{a => 123})).

%% api function
start_link() ->
	Url = <<"ws://localhost:4002/socket/websocket/?">>,
	Params = #{<<"from">> => <<"77877">>, <<"token">> => <<"123456">>},
	Topic = <<"imserver:77877">>,
	Opts = [{url, Url}, {params, Params}, {topic, Topic}],
	gen_server:start_link({local, ?MODULE}, ?MODULE, Opts,[]).

push(Event, Payload) when is_atom(Event) ->
	push(atom_to_binary(Event, utf8), Payload);
push(Event, Payload) when is_list(Event) ->
	push(list_to_binary(Event), Payload);
push(Event, Payload) ->
	gen_server:call(?MODULE, {push, Event, Payload}, 3000).

%%====================================================================
%% gen_server callbacks
%%====================================================================
init(Opts) ->
	State = connect_socket_channel(Opts),
	{ok, State}.

handle_call({push, Event, Payload}, _From, #{channel_pid := Pid, is_connect := true} = State) ->
	channel:push(Pid, Event, Payload),
	{reply, ok, State};
 handle_call({push, Event, Payload}, _From, #{opts := Opts} = State) ->
 	case connect_socket_channel(Opts) of
 	#{is_connect := true, channel_pid := Pid} = State1 ->
 		channel:push(Pid, Event, Payload),
 		{reply, ok, State1};
 	_ ->
 		{reply, error, State}
 	end;
    
handle_call(_Msg, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(Msg, State) ->
    io:format("receive message:~p~n", [Msg]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% internal function 
connect_socket_channel(Opts) ->
	Url = proplists:get_value(url, Opts),
	Params = proplists:get_value(params, Opts),
	SocketOpts = [{url, Url}, {params, Params}],
	Topic = proplists:get_value(topic, Opts),
	
	case socket:start_link(SocketOpts) of
	{ok, Socket} ->
		case channel:join(Socket, Topic) of 
		{ok, _Reply, Pid} ->
			io:format("channel client socket connnect success~n"),
			#{is_connect => true, channel_pid => Pid, opts => Opts};
		_ ->
			io:format("channel client join failure~n"),
			#{is_connect => false, opts => Opts}
		end;
	_ ->
		io:format("channel client socket connnect failure~n"),
		#{is_connect => false, opts => Opts}
	end.