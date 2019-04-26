-module(message).
-include("app.hrl").

-export([
		serializer/1, 
		decode/3,
		encode/3,
		join/2, 
		leave/1
]).

serializer(<<"1.0.0">>) ->  message_v1;
serializer(<<"2.0.0">>) -> message_v2.

decode(Serializer, Message, JsonLibrary) ->
	Serializer:decode(JsonLibrary:decode(Message)).

encode(Serializer, Message, JsonLibrary) ->
	JsonLibrary:encode(Serializer:encode(Message)).

join(Topic, Params) ->
	#message{topic = Topic, 
			event = <<"phx_join">>, 
			payload = Params}.

leave(Topic) ->
	#message{topic = Topic, 
			event = <<"phx_leave">>}.	