-module(message_v1).
-include("app.hrl").

-export([decode/1, encode/1]).

decode(Msg) ->
	#message{ref = maps:get(Msg, ref, <<>>), 
			topic = maps:get(Msg, topic, <<>>), 
			event = maps:get(Msg, event, <<>>), 
			payload = maps:get(Msg, payload, <<>>)}.

encode(#message{
			ref = Ref, 
			topic = Topic,
			event = Event,
			payload = Payload }) ->
	#{
		ref => Ref,
		topic => Topic,
		event => Event,
		payload => Payload
	}.