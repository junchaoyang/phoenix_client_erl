-module(message_v2).
-include("app.hrl").

-export([decode/1, encode/1]).

decode([JoinRef, Ref, Topic, Event, Payload | _]) ->
	#message{
			join_ref = JoinRef, 
			ref = Ref,
			topic = Topic, 
			event = Event, 
			payload = Payload
	}.

encode(#message{
			join_ref = JoinRef, 
			ref = Ref,
			topic = Topic, 
			event = Event, 
			payload = Payload}) ->
	[JoinRef, Ref, Topic, Event, Payload].
