%%
%% @copyright 2006-2007 Mikael Magnusson
%% @copyright 2014 Jean Parpaillon
%% @author Mikael Magnusson <mikma@users.sourceforge.net>
%% @author Jean Parpaillon <jean.parpaillon@free.fr>
%% @doc tcp connection gen_server
%%
%% Messages
%% {received, Pid, Data}
%% {closed, Pid}

-module(dbus_transport_tcp).
-compile([{parse_transform, lager_transform}]).

-behaviour(gen_server).


%% api
-export([connect/3]).

%% gen_server callbacks
-export([init/1,
	 code_change/3,
	 handle_call/3,
	 handle_cast/2,
	 handle_info/2,
	 terminate/2]).

-record(state, {sock, owner}).

connect(Host, Port, Options) ->
    gen_server:start_link(?MODULE, [Host, Port, Options, self()], []).

%%
%% gen_server callbacks
%%
init([Host, Port, Options, Owner]) ->
    true = link(Owner),
    case gen_tcp:connect(Host, Port, Options) of
	{ok, Sock} ->
	    ok = inet:setopts(Sock, [{active, once}]),
	    {ok, #state{sock=Sock, owner=Owner}};
	{error, Err} ->
	    lager:error("Error opening socket: ~p~n", [Err]),
	    {error, Err}
    end.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


handle_call({setopts, Options}, _From, State) ->
    ok = inet:setopts(State#state.sock, Options),
    {reply, ok, State};

handle_call(Request, _From, State) ->
    error_logger:error_msg("Unhandled call in ~p: ~p~n", [?MODULE, Request]),
    {reply, ok, State}.


handle_cast({send, Data}, State) ->
    Sock = State#state.sock,
    gen_tcp:send(Sock, Data),
    {noreply, State};

handle_cast(close, State) ->
    ok = gen_tcp:close(State#state.sock),
    {stop, normal, State#state{sock=undefined}};
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(Request, State) ->
    error_logger:error_msg("Unhandled cast in ~p: ~p~n", [?MODULE, Request]),
    {noreply, State}.


handle_info({tcp, Sock, Data}, #state{sock=Sock}=State) ->
    Owner = State#state.owner,
    Owner ! {received, Data},
    ok = inet:setopts(Sock, [{active, once}]),
    {noreply, State};

handle_info({tcp_closed, Sock}, #state{sock=Sock}=State) ->
    Owner = State#state.owner,
    Owner ! closed,
    {stop, normal, State#state{sock=undefined}};

handle_info(Info, State) ->
    error_logger:error_msg("Unhandled info in ~p: ~p~n", [?MODULE, Info]),
    {noreply, State}.


terminate(_Reason, State) ->
    Sock = State#state.sock,
    case Sock of
	undefined -> ignore;
	_ -> gen_tcp:close(Sock)
    end,
    terminated.