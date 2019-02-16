%%%-------------------------------------------------------------------
%%% @author Vladislav Vorobyov <vlad@erldev>
%%% @copyright (C) 2019, Vladislav Vorobyov
%%% @doc
%%%
%%% @end
%%% Created : 11 Feb 2019 by Vladislav Vorobyov <vlad@erldev>
%%%-------------------------------------------------------------------
-module(rabbit_1c_app).

-behaviour(application).

%% Application callbacks
-export([start/0, stop/0, start/2, stop/1]).

%%%===================================================================
%%% Application callbacks
%%%===================================================================

start() ->
    _ = rabbit_1c_sup:start_link(),
    ok.

stop() -> ok.

start(normal, []) ->
    rabbit_1c_sup:start_link().

stop(_State) -> ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================
