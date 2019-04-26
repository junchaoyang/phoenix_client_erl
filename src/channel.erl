-module(channel).
-behaviour(gen_server).

-define(TIMEOUT, 5000).
-include("app.hrl").

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
	child_spec/1,
	start_link/3,
	stop/1,
  join/2,
  join/4,
  leave/1,
  push/3,
  push_async/3
]).


child_spec({Socket, Topic, Params}) ->
    #{
      id => iolist_to_binary([erlang:atom_to_list(?MODULE), Topic]),
      start => {?MODULE, start_link, [Socket, Topic, Params]},
      restart => temporary
    }.	

start_link(Socket, Topic, Params) ->
    gen_server:start_link(?MODULE, {Socket, Topic, Params}, []).

stop(Pid) ->
	leave(Pid).

join(SocketPidOrName, Topic) ->
	join(SocketPidOrName, Topic, #{}, ?TIMEOUT).
join(nil, _Topic, _Params, _Timeout) ->
	{error, socket_not_started};
join(ScoketName, Topic, Params, Timeout) when is_atom(ScoketName)->
	join(erlang:whereis(ScoketName), Topic, Params, Timeout);
join(SocketPid, Topic, Params, Timeout) ->
	case {erlang:is_process_alive(SocketPid), socket:connected(SocketPid)} of
	{true, true} ->
		case channel_sup:start_channel(SocketPid, Topic, Params) of
		{ok, Pid} -> do_join(Pid, Timeout);
		Error -> Error
		end;
	_NotAliveOrNotConnected ->
		{error, socket_not_connected}
	end.

leave(Pid) ->
	gen_server:call(Pid, leave),
	gen_server:stop(Pid).

push(Pid, Event, Payload) ->
    gen_server:call(Pid, {push, Event, Payload}, ?TIMEOUT).

push_async(Pid, Event, Payload) ->
    gen_server:cast(Pid, {push, Event, Payload}).

%%====================================================================
%% gen_server callbacks
%%====================================================================
init({Socket, Topic, Params}) ->
	{ok, #{
	    caller => nil,
      socket => Socket,
      topic => Topic,
      params => Params,
      pushes => [],
      join_ref => nil
	}}.

handle_call(
        join,
        {Pid, _ref} = From,
        #{socket := Socket, topic := Topic, params := Params} = State
      ) ->
    case socket:channel_join(Socket, self(), Topic, Params) of
    {ok, Push} ->
    	PushMap = #{join_ref => Push#message.ref,
          				caller => Pid,
          				pushes => [{From, Push} | maps:get(pushes, State)]},
    	State1 = maps:merge(State, PushMap),
      {reply, {ok, ok}, State1};
    Error ->
        {reply, Error, State}
    end;

handle_call(leave, _from, #{socket := Socket, topic:= Topic} = State) ->
    socket:channel_leave(Socket, self(), Topic),
    {reply, ok, State};


handle_call({push, Event, Payload}, From, 
		#{socket := Socket, topic := Topic} = State) ->
    Message = #message{
		    topic = Topic,
        event = Event,
        payload = Payload,
        join_ref = maps:get(join_ref, State)
    },
    Push = socket:push(Socket, Message),
    State1 = maps:update(pushes, [{From, Push} | maps:get(pushes, State)], State),
    {reply, ok, State1}.

handle_cast({push, Event, Payload},  
		#{socket := Socket, topic := Topic} = State) ->
    Message = #message{
		topic = Topic,
        event = Event,
        payload = Payload,
        channel_pid = self(),
        join_ref = maps:get(join_ref, State)
    },
    socket:push(Socket, Message),
    {noreply, State}.

handle_info(#message{event = <<"phx_reply">>, ref = Ref} = Msg, #{pushes:= Pushes} = State) ->
    Fun = 
    fun({FromRef, Push}, Acc) -> 
        case Push#message.ref of
        Ref ->
          % #{<<"status">> := Status, <<"response">> := Response} = Msg#message.payload,
          {[{<<"response">>, Response},{<<"status">>, Status} | _]}  = Msg#message.payload,
          gen_server:reply(FromRef, {erlang:binary_to_atom(Status, utf8), Response}),
          proplists:delete(FromRef, Acc);
        _ ->
          Acc
        end
      end,
    Pushes1 = lists:foldl(Fun, Pushes, Pushes),
    {noreply, maps:update(pushes, Pushes1, State)};

handle_info(#message{} = Message, #{caller:= Pid, topic:= Topic} = State) ->
    erlang:send(Pid, Message#message{channel_pid = Pid, topic = Topic}),
    {noreply, State};

handle_info(_Message, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% internal function
do_join(Pid, Timeout) ->
	  try
        case gen_server:call(Pid, join, Timeout) of
        {ok, Reply} ->
          erlang:link(Pid),
          {ok, Reply, Pid};

        Error ->
          stop(Pid),
          Error
        end
	  catch _Class:Reason ->
		    stop(Pid),
		    {error, exit_reason(Reason)}
	   end.

exit_reason({timeout, _}) -> timeout;
exit_reason(Reason) -> Reason.