%%%-------------------------------------------------------------------
%%% @author Vladislav Vorobyov <vlad@erldev>
%%% @copyright (C) 2019, Vladislav Vorobyov
%%% @doc
%%%
%%% @end
%%% Created : 11 Feb 2019 by Vladislav Vorobyov <vlad@erldev>
%%%-------------------------------------------------------------------
-module(rabbit_1c_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

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
-spec start_link() -> {ok, Pid :: pid()} |
		      {error, {already_started, Pid :: pid()}} |
		      {error, {shutdown, term()}} |
		      {error, term()} |
		      ignore.
start_link() ->
    case rabbit_1c_config:parse_configuration() of
	{ok, Configuration} ->
	    io:format("~n~p",[Configuration]),
	    supervisor:start_link({local, ?SERVER}, ?MODULE, Configuration);
	{error, Reason} ->
	    {error, Reason}
    end.

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
init(Config) ->
    SupFlags = #{strategy => one_for_one,
		 intensity => 1,
		 period => 5},
    ChildSpecs = [#{id => rabbit_1c_status,
		    start => {rabbit_1c_status,start_link, []},
		    restart => permanent,
		    shutdown => 16#ffffffff,
		    type => worker,
		    module => [rabbit_1c_dyn_worker_sup_sup]},
		  #{id=> rabbit_1c_dest_sup,
		    start => {rabbit_1c_dest_sup, start_link, []},
		    restart => permanent,
		    shutdown => 16#ffffffff,
		    type => supervisor,
		    module => [rabbit_1c_dest_sup]},
		  #{id => rabbit_1c_dyn_worker_sup_sup,
		    start => {rabbit_1c_dyn_worker_sup_sup,start_link, []},
		    restart => permanent,
		    shutdown => 16#ffffffff,
		    type =>supervisor,
		    module => [rabbit_1c_dyn_worker_sup_sup]},
		  #{id => rabbit_1c_worker_sup_sup,
		    start => {rabbit_1c_worker_sup_sup,start_link, [Config]},
		    restart => permanent,
		    shutdown => 16#ffffffff,
		    type =>supervisor,
		    module => [rabbit_1c_worker_sup_sup]}
		   ],
    {ok, {SupFlags, ChildSpecs}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
