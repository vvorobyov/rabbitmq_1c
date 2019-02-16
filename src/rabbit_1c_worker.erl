%%%-------------------------------------------------------------------
%%% @author Vladislav Vorobyov <vlad@erldev>
%%% @copyright (C) 2019, Vladislav Vorobyov
%%% @doc
%%%
%%% @end
%%% Created : 11 Feb 2019 by Vladislav Vorobyov <vlad@erldev>
%%%-------------------------------------------------------------------
-module(rabbit_1c_worker).

-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").


%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 handle_continue/2,
	 terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).

-record(state, {name,
		type,
		ack_mode,
		src_uri,
		dst_uri,
		amqp_params,
		vhost,
		queue,
		conn,
		ch,
		wait_ask=[],
		cons_tag}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%% @end
%%--------------------------------------------------------------------
-spec start_link(Name :: atom(), Config :: map()) ->
			{ok, Pid :: pid()} |
			{error, Error :: {already_started, pid()}} |
			{error, Error :: term()} |
			ignore.
start_link(Name, Config = #{type:=Type}) ->
    ok = rabbit_1c_status:report(Name, Type, starting),
    gen_server:start_link(?MODULE, [Name, Config], []).

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
init([Name, #{type := Type,
	      ack_mode := Ack,
	      source := Source,
	      queue := Queue,
	      dest := Dest}]) ->
    AmqpParam = parse_uri(Source),
    VHost = get_vhost(AmqpParam),
    {ok, #state{name = Name,
		type = Type,
		ack_mode = Ack,
		amqp_params = AmqpParam,
		vhost = to_binary(VHost),
		queue = to_binary(Queue),
		src_uri = Source,
		dst_uri = Dest},
     {continue, init}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%% @end
%%--------------------------------------------------------------------
-spec handle_continue(Request :: term(), State :: term()) ->
			 {noreply, NewState :: term()} |
			 {noreply, NewState :: term(), Timeout :: timeout()} |
			 {noreply, NewState :: term(), hibernate} |
			 {stop, Reason :: term(), NewState :: term()}.
handle_continue(init, S=#state{}) ->
    {Conn, Ch, URI} = make_conn_and_ch(S),
    process_flag(trap_exit, true),
    {noreply, S#state{conn=Conn, ch=Ch, src_uri=URI},
    {continue, consume}};
handle_continue(declare, S=#state{conn=Conn}) ->
    {ok, Ch} = amqp_connection:open_channel(Conn),
    declare_queue(Ch, S#state.queue),
    {noreply, S#state{ch = Ch}, {continue, consume}};
handle_continue(consume, S=#state{})->
    consume_queue(S#state.ch, S#state.queue, S#state.ack_mode),
    report_running(S),
    {noreply, S}.

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
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

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
handle_cast(_Request, State) ->
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
handle_info(#'basic.consume_ok'{consumer_tag=ConsTag}, S) ->
    {noreply, S#state{cons_tag=ConsTag}};
handle_info(Msg = {#'basic.deliver'{consumer_tag = ConsTag,
				    delivery_tag = DelTag},_},
	    S = #state{cons_tag=ConsTag}) ->
    NoAckFun = fun () ->
		       amqp_channel:cast(S#state.ch,
					 #'basic.nack'{delivery_tag=DelTag})
	       end,
    AckFun = fun () ->
		     amqp_channel:cast(S#state.ch,
				       #'basic.ack'{delivery_tag=DelTag})
	     end,
    {ok, Pid} =
	rabbit_1c_dest_sup:publish_message(S#state.dst_uri,
					   S#state.vhost,
					   S#state.queue,
					   Msg, #{nack => NoAckFun,
						  ack => AckFun}),
    Ref = erlang:monitor(process, Pid),
{noreply, S#state{wait_ask = [{Ref, NoAckFun}|S#state.wait_ask]}};
handle_info({'EXIT', Conn, Reason}, #state{conn = Conn}) ->
    {stop, {inbound_conn_died, Reason}};
handle_info({'EXIT', Ch, {shutdown, {_,Code, Reason}}}, S=#state{ch = Ch}) ->
    rabbit_1c_status:report(S#state.name, S#state.type,
			    {terminated, Reason}),
    io:format("~nStop code: ~p", [Code]),
    case Code of
	404 ->
	    rabbit_log:error("RabbitMQ to 1C plugin "
			     "Error consume to queue with reason: ~p (404)",
			     [Reason]),
	    {noreply, S, {continue, declare}};
	_ ->
	    rabbit_log:warning("RabbitMQ to 1C plugin "
			       "Channel close with reason: ~p (~p)",
			       [Reason, Code]),
	    {ok,NewCh} = amqp_connection:open_channel(S#state.conn),
	    rabbit_log:warning("RabbitMQ to 1C plugin "
			       "Channel restart"),
	    {noreply, S#state{ch=NewCh}, {continue, consume}}
    end;
handle_info({'DOWN', Ref, process, _Pid, Reason}, S=#state{wait_ask=WA})
  when is_reference(Ref) ->
    Val = proplists:lookup(Ref, WA),
    case {Reason,Val} of
	{_, none}           -> {noreply, S};
	{normal, _}         -> {noreply, S#state{wait_ask=WA--[Val]}};
	{_, {Ref, NAckFun}} -> NAckFun(),
			       {noreply, S#state{wait_ask=WA--[Val]}}
    end;
handle_info(Info, State) ->
    rabbit_log:info("RabbitMQ to 1C plugin "
		    "Undefined handle info: ~p",[Info]),
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

terminate(Reason, S) ->
    close_connection(S#state.conn),
    rabbit_log:info("RabbitMQ to 1C plugin. "
		    "Terminating ~p worker '~p' with  ~p",
		    [S#state.type, S#state.name, Reason]),
    rabbit_1c_status:remove(S#state.name),
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
make_conn_and_ch(S=#state{}) ->
    try do_make_conn_and_chan(S#state.type,
			      S#state.name,
			      S#state.amqp_params,
			      S#state.queue,
			      S#state.src_uri)
    of
	Val -> Val
    catch
	throw:{error, Reason, URI} ->
	    rabbit_log:error("RabbitMQ to 1C plugin. "
			     "Worker '~p', cann't start"
			     " connection (URI=~p) with reason: ~p",
			     [S#state.name,
			      amqp_uri:remove_credentials(URI),
			      Reason]),
	    exit(failed_to_connect_using_provided_uris)
    end.

do_make_conn_and_chan(Type, Name, AmqpParam, Queue, URI)->
    VHost = get_vhost(AmqpParam),
    ConnName = get_conn_name(Type, Name, VHost, Queue),
    case amqp_connection:start(AmqpParam, ConnName) of
	{ok, Conn} ->
	    link(Conn),
	    {ok, Ch} = amqp_connection:open_channel(Conn),
	    link(Ch),
	    {Conn, Ch, list_to_binary(amqp_uri:remove_credentials(URI))};
	{error, not_allowed} ->
	    throw({error, not_allowed, URI});
	{error, Reason} ->
	    throw({error, Reason, URI})
    end.

close_connection(Conn)->
    amqp_connection:close(Conn).

consume_queue(Ch, Queue, AckMode) ->
    #'basic.qos_ok'{} =
	amqp_channel:call(Ch, #'basic.qos'{prefetch_count = 1000}),
    (catch #'basic.consume_ok'{} =
	 amqp_channel:subscribe(
	   Ch, #'basic.consume'{queue = Queue,
				no_ack = AckMode =:= no_ack}, self())),
     ok.
declare_queue(Ch, Queue)->
    #'queue.declare_ok'{} =
	amqp_channel:call(Ch, #'queue.declare'{queue = Queue}).
    

get_conn_name(Type0, Name, VHost0, Queue)->
    VHost = to_binary(VHost0),
    Type = to_binary(Type0),
    ConnName = io_lib:format("RabbitMQ to 1C ~s '~s' (vhost - '~s', "
			     "queue - '~s')", [Type, Name, VHost, Queue]),
    erlang:iolist_to_binary(ConnName).

parse_uri(URI)->
    case amqp_uri:parse(URI) of
	{error, {Info, URI}} ->
	    throw({error, Info, URI});
	{ok, Val} ->
	    Val
    end.

get_vhost(AmqpParam) ->
    case AmqpParam of
	#amqp_params_network{} ->
		AmqpParam#amqp_params_network.virtual_host;
	#amqp_params_direct{} ->
	    AmqpParam#amqp_params_direct.virtual_host
    end.

to_binary(V) when is_binary(V) ->
    V;
to_binary(V) when is_atom(V)->
    erlang:atom_to_binary(V, unicode);
to_binary(V) when is_list(V) ->
    erlang:list_to_binary(V).

report_running(S=#state{})->
    rabbit_1c_status:report(
      S#state.name, S#state.type,
      {running, [{src_uri, rabbit_data_coercion:to_binary(S#state.src_uri)},
		{dst_uri, remove_credentials(S#state.dst_uri)}]}).

remove_credentials(URI)->
    {ok, {Protocol, _, Host, Port, Path, Qs}}=http_uri:parse(URI),
    erlang:iolist_to_binary(
      io_lib:format("~s://~s:~p~s~s", [Protocol, Host, Port, Path, Qs])).


