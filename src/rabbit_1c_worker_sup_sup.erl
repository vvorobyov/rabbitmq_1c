%%%-------------------------------------------------------------------
%%% @author Vladislav Vorobyov <vlad@erldev>
%%% @copyright (C) 2019, Vladislav Vorobyov
%%% @doc
%%%
%%% @end
%%% Created : 14 Feb 2019 by Vladislav Vorobyov <vlad@erldev>
%%%-------------------------------------------------------------------
-module(rabbit_1c_worker_sup_sup).

-behaviour(mirrored_supervisor).

%% API
-export([start_link/1, restart_child/1]).

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
-spec start_link(Config :: map()) -> {ok, Pid :: pid()} |
		      {error, {already_started, Pid :: pid()}} |
		      {error, {shutdown, term()}} |
		      {error, term()} |
		      ignore.
start_link(Config) ->
    Pid = case mirrored_supervisor:start_link(
		 {local, ?SERVER}, ?SERVER,
		 fun rabbit_misc:execute_mnesia_transaction/1,
		 ?MODULE, [Config]) of
	      {ok, Pid0} -> Pid0;
	      {error,{alredy_started, Pid0}} -> Pid0
	  end,
    {ok, Pid}.


restart_child(Name) ->
    mirrored_supervisor:terminate_child(?SERVER, Name),
    mirrored_supervisor:restart_child(?SERVER, Name).
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
init([Config]) ->
    {ok, {{one_for_one, 3, 10}, make_child_specs(Config)}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
make_child_specs(Sources=#{})->
    Fun = fun (Name, Config, Acc) ->
		  Spec = {Name,
			  {rabbit_1c_worker_sup,start_link,[Name, Config]},
			  permanent, 16#ffffffff, supervisor,
			  [rabbit_1c_worker_sup]},
		  [Spec|Acc]
	  end,
    lists:reverse(maps:fold(Fun, [], Sources)).

