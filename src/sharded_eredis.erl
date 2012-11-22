%%%-------------------------------------------------------------------
%%% @author Jeremy Ong <jeremy@playmesh.com>
%%% @copyright (C) 2012, PlayMesh, Inc.
%%%-------------------------------------------------------------------

-module(sharded_eredis).

%% Include
-include_lib("eunit/include/eunit.hrl").

%% Default timeout for calls to the client gen_server
%% Specified in http://www.erlang.org/doc/man/gen_server.html#call-3
-define(TIMEOUT, 5000).

%% API
-export([start/0, stop/0]).
-export([q/1, q/2, q2/2, q2/3, transaction/2]).

%%%===================================================================
%%% API functions
%%%===================================================================

start() ->
    application:start(?MODULE).

stop() ->
    application:stop(?MODULE).

%%--------------------------------------------------------------------
%% @doc
%% Executes the given command in the specified connection. The
%% command must be a valid Redis command and may contain arbitrary
%% data which will be converted to binaries. The returned values will
%% always be binaries.
%% @end
%%--------------------------------------------------------------------


-spec q(Command::iolist()) ->
    {ok, binary() | [binary()]} | {error, Reason::binary()}.

q(Command) ->
    q(Command, ?TIMEOUT).

-spec q(Command::iolist(), Timeout::integer()) ->
    {ok, binary() | [binary()]} | {error, Reason::binary()}.

q(Command = [_, Key|_], Timeout) ->
    Node = sharded_eredis_chash:lookup(Key),
    poolboy:transaction(Node, fun(Worker) ->
                                      eredis:q(Worker, Command, Timeout)
                              end).

transaction(Key, Fun) when is_function(Fun) ->
    Node = sharded_eredis_chash:lookup(Key),
    F = fun(C) ->
                try
                  {ok, <<"OK">>} = eredis:q(C, ["MULTI"]),
                  Fun(),
                  eredis:q(C, ["EXEC"])
                catch C:Reason ->
                       {ok, <<"OK">>} = eredis:q(C, ["DISCARD"]),
                       io:format("Error in redis transaction. ~p:~p", 
                                 [C, Reason]),
                       {error, Reason}
               end
    end,

    poolboy:transaction(Node, F).    

-spec q2(Node::term(), Command::iolist()) ->
    {ok, binary() | [binary()]} | {error, Reason::binary()}.
q2(Node, Command) ->
    q2(Node, Command, ?TIMEOUT).

-spec q2(Node::term(), Command::iolist(), Timeout::integer()) ->
    {ok, binary() | [binary()]} | {error, Reason::binary()}.
q2(Node, Command, Timeout) ->
    poolboy:transaction(Node, fun(Worker) ->
                                      eredis:q(Worker, Command, Timeout)
                              end).
