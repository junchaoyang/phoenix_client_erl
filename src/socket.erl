-module(socket).
-behaviour(gen_server).

-include("app.hrl").
-define(HEARTBEAT_INTERVAL, 10000).
-define(RECONNECT_INTERVAL, 25000).
-define(DEFAULT_TRANSPORT, websocket).

%% gen_server callback
-export([
  	init/1, 
  	handle_call/3, 
  	handle_cast/2,
   	handle_info/2, 
   	terminate/2,
   	code_change/3
]).

%% api
-export([
	  child_spec/1,
    start_link/1,
    start_link/2,
    stop/1,
    connected/1,
    push/2,
    channel_join/4,
    channel_leave/3
]).

child_spec({Opts, GenServerOpts}) ->
	  #{id => maps:get(id, GenServerOpts, ?MODULE),
      start => {?MODULE, start_link, [Opts, GenServerOpts]}};

child_spec(Opts) ->
  child_spec({Opts, []}).


start_link(Opts) ->
    start_link(Opts, []).
start_link(Opts, GenServerOpts) ->
    gen_server:start_link(?MODULE, Opts, GenServerOpts).

stop(Pid) ->
    gen_server:stop(Pid).

connected(Pid) ->
    gen_server:call(Pid, status) == connected.

push(Pid, #message{} = Message) ->
    gen_server:call(Pid, {push, Message}).

channel_join(Pid, Channel, Topic, Params) ->
    gen_server:call(Pid, {channel_join, Channel, Topic, Params}).

channel_leave(Pid, Channel, Topic) ->
    gen_server:call(Pid, {channel_leave, Channel, Topic}).


%%====================================================================
%% gen_server callbacks
%%====================================================================
init(Opts) ->
    crypto:start(),
    ssl:start(),

    Transport = proplists:get_value(transport, Opts, ?DEFAULT_TRANSPORT),
    
    JsonLibrary = proplists:get_value(json_library, Opts, jiffy),
    Reconnect = proplists:get_value(reconnect, Opts, true),

    ProtocolVsn = proplists:get_value(vsn, Opts, <<"2.0.0">>),
    Serializer = message:serializer(ProtocolVsn),

    Url = proplists:get_value(url, Opts, <<>>),

    Params = proplists:get_value(params, Opts, #{}),
    Params1 = maps:put(<<"vsn">>, ProtocolVsn, Params),

    Fun = fun(Key, Value, Acc) -> lists:append(["&", erlang:binary_to_list(Key), "=", erlang:binary_to_list(Value), Acc]) end,
    [_And |Params2] = maps:fold(Fun, [], Params1),

    Url1 = iolist_to_binary([Url, Params2]),

    HeartbeatInterval = proplists:get_value(heartbeat_interval, Opts, ?HEARTBEAT_INTERVAL),
    ReconnectInterval = proplists:get_value(heartbeat_interval, Opts, ?RECONNECT_INTERVAL),

    TransportOpts = [{sender, self()} | proplists:get_value(transport_opts, Opts, [])],
    erlang:send(self(), connect),

    {ok,
     #{
       opts => [{headers, []}| Opts],
       url => Url1,
       json_library => JsonLibrary,
       params => Params,
       channels => #{},
       reconnect => Reconnect,
       heartbeat_interval => HeartbeatInterval,
       reconnect_interval => ReconnectInterval,
       reconnect_timer => nil,
       status => disconnected,
       serializer => Serializer,
       transport => Transport,
       transport_opts => TransportOpts,
       transport_pid => nil,
       queue => queue:new(),
       ref => 0
     }}.


handle_call({push, #message{} = Message}, _from, State) ->
    {Push, State1} = push_message(Message, State),
    {reply, Push, State1};

handle_call(
        {channel_join, ChannelPid, Topic, Params},
        _From,
        #{channels := Channels} = State
      ) ->
    case maps:get(Topic, Channels, nil) of
      nil ->
        MonitorRef = erlang:monitor(process, ChannelPid),
        Message = message:join(Topic, Params),
        {Push, State1} = push_message(Message, State),
        Channels1 = maps:put(Topic, {ChannelPid, MonitorRef}, Channels),
        State2 = maps:update(channels, Channels1, State1),
        {reply, {ok, Push}, State2};
      {Pid, _topic} ->
        {reply, {error, {already_joined, Pid}}, State}
    end;

handle_call({channel_leave, _channel, Topic}, _from, 
  #{channels := Channels} = State) ->
    case maps:get(Topic, Channels, nil) of
    nil ->
        {reply, error, State};
    {_ChannelPid, MonitorRef} ->
        erlang:demonitor(MonitorRef),
        Message = message:leave(Topic),
        {Push, State} = push_message(Message, State),
        Channels1 = maps:remove(Topic, Channels),
        State1 = maps:update(channels, Channels1, State),
        {reply, {ok, Push}, State1}
    end;

handle_call(status, _from, #{status := Status} = State) ->
    {reply, Status, State}.

handle_cast(_Msg, State) -> 
    {noreply, State}.


handle_info({connected, TransportPid}, #{transport_pid := TransportPid,
                                      heartbeat_interval := HeartbeatInterval} = State) ->
    erlang:send_after(HeartbeatInterval, self(), heartbeat),
    {noreply, maps:update(status, connected, State)};

handle_info({disconnected, Reason, TransportPid}, #{transport_pid := TransportPid} = State) ->
    {noreply, close(Reason, State)};

handle_info(heartbeat, #{status := connected, 
                        ref := Ref0,
                        heartbeat_interval := HeartbeatInterval} = State) ->
    Ref = Ref0 + 1,

    Message = #message{topic = <<"phoenix">>, 
                      event = <<"heartbeat">>, 
                      ref = Ref},
    transport_send(Message, State),

    erlang:send_after(HeartbeatInterval, self(), heartbeat),
    {noreply, maps:update(ref, Ref, State)};

handle_info(heartbeat, State) ->
    {noreply, State};

handle_info({'receive', Message}, State) ->
    transport_receive(Message, State),
    {noreply, State};

handle_info(flush, #{status := connected} = State) ->
    State1 = 
    case queue:out(maps:get(queue, State)) of 
    {empty, _queue} ->
        State;
    {{value, Message}, Queue} ->
        transport_send(Message, State),
        erlang:send_after(100, self(), flush),
        maps:update(queue, Queue, State)
    end,
    {noreply, State1};

handle_info(flush, State) ->
    erlang:send_after(100, self(), flush),
    {noreply, State};

handle_info(connect, #{transport := Transport, 
                      transport_opts := Opts,
                      url := Url} = State) ->
    case Transport:open(Url, Opts) of
    {ok, TransportPid} ->
        MapNew = #{transport_pid => TransportPid, 
                  reconnect_timer => nil,
                  status => connected},
        erlang:send(self(), {connected, TransportPid}),
        {noreply, maps:merge(State, MapNew)};
    {error, Reason} ->
      {noreply, close(Reason, State)}
    end;

handle_info({closed, Reason, TransportPid}, 
            #{transport_pid := TransportPid} = State) ->
    {noreply, close(Reason, State)};

handle_info({'DOWN', _MonitorRef, 'process', Pid, _reason}, 
          #{channels := Channels}= State) ->
    Pred = fun(_Topic, {ChannelPid, _}) -> ChannelPid == Pid end,

    case maps:filter(Pred, Channels) of 
    #{} ->
        {noreply, State};
    {Topic, _} ->
        Message = message:leave(Topic),
        {_Push, State1} = push_message(Message, State),
        Channels1 = maps:remove(Topic, Channels),
        State1 = maps:update(channels, Channels1, State),
        {noreply, State1}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% internal function 
transport_receive(Message, #{channels := Channels, 
                          serializer := Serializer,
                          json_library := JsonLibrary
                            }) ->
    Decoded = message:decode(Serializer, Message, JsonLibrary),
    case maps:get(Decoded#message.topic, Channels, false) of
    false ->
        noop;
    {ChannelPid, _} -> 
        erlang:send(ChannelPid, Decoded)
    end.

transport_send(Message, #{transport_pid := Pid, 
                          serializer := Serializer,
                          json_library := JsonLibrary
                          }) ->
    erlang:send(Pid, {send, message:encode(Serializer, Message, JsonLibrary)}).

close(Reason, #{channels := Channels, reconnect_timer := nil} = State) ->
    State1 = maps:update(status, disconnected, State),
    Message = #message{event = close_event(Reason), payload = #{reason => Reason}},

    maps:fold(
        fun(_Key, {ChannlePid, _MonitorRef} , _Acc) ->
                erlang:send(ChannlePid, Message)
        end, 0, Channels),

    Reconnect = maps:get(reconnect, State1),
    if Reconnect ->
        Time = maps:get(reconnect_interval, State1),
        TimerRef = erlang:send_after(Time, self(), connect),
        maps:update(reconnect_timer, TimerRef, State1);
    true ->
      State1
    end.


close_event(normal) -> <<"phx_close">>;
close_event(_) -> <<"phx_error">>.

push_message(Message, #{ref := Ref0, queue := Queue0} = State) ->
    Ref = Ref0 + 1,
    Push = Message#message{ref = erlang:integer_to_binary(Ref)},
    erlang:send(self(), flush),
    State1 = maps:merge(State, #{ref => Ref, queue => queue:in(Push, Queue0)}),
    {Push, State1}.