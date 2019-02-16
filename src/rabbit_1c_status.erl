%%%-------------------------------------------------------------------
%%% @author Vladislav Vorobyov <vlad@erldev>
%%% @copyright (C) 2019, Vladislav Vorobyov
%%% @doc
%%%
%%% @end
%%% Created : 14 Feb 2019 by Vladislav Vorobyov <vlad@erldev>
%%%-------------------------------------------------------------------
-module(rabbit_1c_status).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([report/3, remove/1, status/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).
-define(ETS_NAME, ?MODULE).

-record(state, {}).
-record(entry, {name, type, info, timestamp}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, Pid :: pid()} |
		      {error, Error :: {already_started, pid()}} |
		      {error, Error :: term()} |
		      ignore.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Register report
%% @end
%%--------------------------------------------------------------------
report(Name, Type, Info)->
    gen_server:cast(?SERVER,
		    {report, Name, Type, Info, calendar:local_time()}).

%%--------------------------------------------------------------------
%% @doc
%% Register remove worker
%% @end
%%--------------------------------------------------------------------
remove(Name)->
    gen_server:cast(?SERVER, {remove, Name}).

%%--------------------------------------------------------------------
%% @doc
%% Get workers status
%% @end
%%--------------------------------------------------------------------
status()->
    gen_server:call(?SERVER, status, infinity).
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%% @end
%%--------------------------------------------------------------------
-spec init(Args :: term()) -> {ok, State :: term()} |
			      {ok, State :: term(), Timeout :: timeout()} |
			      {ok, State :: term(), hibernate} |
			      {stop, Reason :: term()} |
			      ignore.
init([]) ->
    ?ETS_NAME = ets:new(?ETS_NAME,
		       [named_table, {keypos, #entry.name}, private]),
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request :: term(), From :: {pid(), term()}, State :: term()) ->
			 {reply, Reply :: term(), NewState :: term()} |
			 {reply, Reply :: term(), NewState :: term(), Timeout :: timeout()} |
			 {reply, Reply :: term(), NewState :: term(), hibernate} |
			 {noreply, NewState :: term()} |
			 {noreply, NewState :: term(), Timeout :: timeout()} |
			 {noreply, NewState :: term(), hibernate} |
			 {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
			 {stop, Reason :: term(), NewState :: term()}.

handle_call(status, _From, State) ->
    Entries = ets:tab2list(?ETS_NAME),
    {reply, [{Entry#entry.name, Entry#entry.type, Entry#entry.info,
	     Entry#entry.timestamp} || Entry <-Entries], State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Request :: term(), State :: term()) ->
			 {noreply, NewState :: term()} |
			 {noreply, NewState :: term(), Timeout :: timeout()} |
			 {noreply, NewState :: term(), hibernate} |
			 {stop, Reason :: term(), NewState :: term()}.
handle_cast({report, Name, Type, Info, Timestamp}, State) ->
    true = ets:insert(?ETS_NAME, #entry{name = Name, type = Type,
					info = split_status(Info),
					timestamp = Timestamp}),
    rabbit_event:notify(rabbit_1c_worker_status,
		       split_name(Name) ++ split_status(Info)),
    {noreply, State};
handle_cast({remove, Name}, State) ->
    true = ets:delete(?ETS_NAME, Name),
    rabbit_event:notify(rabbit_1c_worker_removed, split_name(Name)),
    {noreply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info :: timeout() | term(), State :: term()) ->
			 {noreply, NewState :: term()} |
			 {noreply, NewState :: term(), Timeout :: timeout()} |
			 {noreply, NewState :: term(), hibernate} |
			 {stop, Reason :: normal | term(), NewState :: term()}.
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%% @end
%%--------------------------------------------------------------------
-spec terminate(Reason :: normal | shutdown | {shutdown, term()} | term(),
		State :: term()) -> any().
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn :: term() | {down, term()},
		  State :: term(),
		  Extra :: term()) -> {ok, NewState :: term()} |
				      {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called for changing the form and appearance
%% of gen_server status when it is returned from sys:get_status/1,2
%% or when it appears in termination error logs.
%% @end
%%--------------------------------------------------------------------
-spec format_status(Opt :: normal | terminate,
		    Status :: list()) -> Status :: term().
format_status(_Opt, Status) ->
    Status.

%%%===================================================================
%%% Internal functions
%%%===================================================================
split_status({running, MoreInfo}) -> [{status, running} |MoreInfo];
split_status({terminated, Reason}) -> [{status, terminated},
				       {reason, Reason}];
split_status(Status) when is_atom(Status)-> [{status, Status}].

split_name({VHost, Name}) -> [{name, Name},
			      {vhost, VHost}];
split_name(Name) when is_atom(Name) -> [{name, Name}];
split_name(Name) when is_binary(Name) -> [{name, Name}].
