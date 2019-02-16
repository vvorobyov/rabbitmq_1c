%%%-------------------------------------------------------------------
%%% @author Vladislav Vorobyov <vlad@erldev>
%%% @copyright (C) 2019, Vladislav Vorobyov
%%% @doc
%%%
%%% @end
%%% Created : 11 Feb 2019 by Vladislav Vorobyov <vlad@erldev>
%%%-------------------------------------------------------------------
-module(rabbit_1c_worker_sup).

-behaviour(supervisor2).

%% API
-export([start_link/2]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%% @end
%%--------------------------------------------------------------------
-spec start_link(Name :: atom(), Config :: map()) ->
			{ok, Pid :: pid()} |
			{error, {already_started, Pid :: pid()}} |
			{error, {shutdown, term()}} |
			{error, term()} |
			ignore.
start_link(Name, Config) ->
    supervisor2:start_link(?SERVER, [Name, Config]).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart intensity, and child
%% specifications.
%% @end
%%--------------------------------------------------------------------
-spec init(Args :: term()) ->
		  {ok, {SupFlags :: supervisor:sup_flags(),
			[ChildSpec :: supervisor:child_spec()]}} |
		  ignore.
init([Name, Config = #{reconnect_delay := RecDelay}]) ->
    SupFlags = {one_for_one, 3, 5},
    ChildSpec = {Name,
		 {rabbit_1c_worker, start_link, [Name, Config]},
		 case RecDelay of
		     N when N >0 -> {permanent, N};
		     _ -> temporary
		 end,
		 5000,
		 worker,
		 [rabbit_1c_worker]},
    {ok, {SupFlags, [ChildSpec]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
