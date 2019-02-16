%%%-------------------------------------------------------------------
%%% @author Vladislav Vorobyov <vlad@erldev>
%%% @copyright (C) 2019, Vladislav Vorobyov
%%% @doc
%%%
%%% @end
%%% Created : 14 Feb 2019 by Vladislav Vorobyov <vlad@erldev>
%%%-------------------------------------------------------------------
-module(rabbit_1c_dyn_worker_sup_sup).

-behaviour(mirrored_supervisor).

%% API
-export([start_link/0, adjust/2, stop_child/1, restart_child/1]).

%% Supervisor callbacks
-export([init/1]).

-import(rabbit_misc, [pget/2]).
-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, Pid :: pid()} |
		      {error, {already_started, Pid :: pid()}} |
		      {error, {shutdown, term()}} |
		      {error, term()} |
		      ignore.
start_link() ->
    Pid = case mirrored_supervisor:start_link(
		 {local, ?SERVER}, ?SERVER,
		 fun rabbit_misc:execute_mnesia_transaction/1,
		 ?MODULE, []) of
	      {ok, Pid0} -> Pid0;
	      {error,{alredy_started, Pid0}} -> Pid0
	  end,
    Params = rabbit_runtime_parameters:list_component(<<"rabbitmq_1c">>),
    [start_child(pget(name, Param), pget(value, Param)) || Param <- Params],
    {ok, Pid}.

adjust(Name, Def)->
    case child_exists(Name) of
	true -> stop_child(Name);
	false -> ok
    end,
    start_child(Name, Def).

start_child(Name, Def) ->
    {Name, Config} = rabbit_1c_config:parse_config(dynamic, Name, Def),
    Spec = {Name,
	    {rabbit_1c_worker_sup, start_link, [Name, Config]},
	    transient,
	    16#ffffffff,
	    supervisor,
	    [rabbit_1c_worker_sup]},
    case mirrored_supervisor:start_child(?SERVER, Spec) of
	{ok, _Pid} -> ok;
	{error, {alredy_started, _Pid}} -> ok
    end.

stop_child(Name) ->
    ok = mirrored_supervisor:terminate_child(?SERVER, Name),
    ok = mirrored_supervisor:delete_child(?SERVER, Name),
    rabbit_1c_status:remove(Name).

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
init([]) ->
    {ok, {{one_for_one, 3, 10}, []}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
child_exists(Name) ->
    lists:any(fun({N, _, _, _}) -> N =:= Name end,
	     mirrored_supervisor:which_children(?SERVER)).
