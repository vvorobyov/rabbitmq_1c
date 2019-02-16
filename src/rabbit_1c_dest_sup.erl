%%%-------------------------------------------------------------------
%%% @author Vladislav Vorobyov <vlad@erldev>
%%% @copyright (C) 2019, Vladislav Vorobyov
%%% @doc
%%%
%%% @end
%%% Created : 12 Feb 2019 by Vladislav Vorobyov <vlad@erldev>
%%%-------------------------------------------------------------------
-module(rabbit_1c_dest_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([publish_message/5]).
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
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%--------------------------------------------------------------------
%% @doc
%% Start message publishing
%% @end
%%--------------------------------------------------------------------
publish_message(URI, VHost, Queue, Msg, Funs)->
    supervisor:start_child(?SERVER, [URI, VHost, Queue, Msg, Funs]).
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
    SupFlags = #{strategy => simple_one_for_one,
		 intensity => 1,
		 period => 5},
    Spec = #{id => rabbit_1c_dest_worker,
	     start => {rabbit_1c_dest_worker,start_link, []},
	     restart => temporary,
	     shutdown => 1000,
	     type => worker,
	     modules => [rabbit_1c_dest_worker]},
    %% AChild = #{id => 'AName',
    %% 	       start => {'AModule', start_link, []},
    %% 	       restart => permanent,
    %% 	       shutdown => 5000,
    %% 	       type => worker,
    %% 	       modules => ['AModule']},

    {ok, {SupFlags, [Spec]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
