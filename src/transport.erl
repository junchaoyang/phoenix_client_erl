-module(transport).

-callback open(binary(), tuple()) -> 
	{ok, pid()} | {error, any()}.


-callback close(pid()) -> 
	{ok, any()} | {error, any()}.
