%%%-------------------------------------------------------------------
%%% @author Vladislav Vorobyov <vlad@erldev>
%%% @copyright (C) 2019, Vladislav Vorobyov
%%% @doc
%%%
%%% @end
%%% Created : 12 Feb 2019 by Vladislav Vorobyov <vlad@erldev>
%%%-------------------------------------------------------------------
-module(rabbit_1c_dest_worker).

-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").

%% API
-export([start_link/5]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3, format_status/2, handle_continue/2]).

-define(SERVER, ?MODULE).

-record(state, {uri, vhost, queue, msg, ack, nack, body}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%% @end
%%--------------------------------------------------------------------
-spec start_link(URI :: list(),
		 VHost :: binary(),
		 Queue :: binary(),
		 Msg :: term(),
		 Funs :: map()) ->
			{ok, Pid :: pid()} |
			{error, Error :: {already_started, pid()}} |
			{error, Error :: term()} |
			ignore.
start_link(URI, VHost, Queue, Msg, Funs) ->
    gen_server:start_link(?MODULE, [URI, VHost, Queue, Msg, Funs], []).

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
init([URI,VHost,Queue,Msg,#{nack:=NAck, ack:= Ack}]) ->
						%   {stop, normal}.
    io:format("~nURI: ~p", [URI]),
    {ok, #state{uri=URI,
		vhost=VHost,
		queue=Queue,
		msg=Msg,
		ack=Ack,
		nack=NAck},
     {continue, init}}.

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
%% Handling continue messages
%% @end
%%--------------------------------------------------------------------
-spec handle_continue(Request :: term(), State :: term()) ->
			 {noreply, NewState :: term()} |
			 {noreply, NewState :: term(), Timeout :: timeout()} |
			 {noreply, NewState :: term(), hibernate} |
			 {stop, Reason :: term(), NewState :: term()}.
handle_continue(init, S) ->
    JSON0 = make_json(S#state.vhost, S#state.queue, S#state.msg),
    JSON = jsx:encode(JSON0),
    {noreply,S#state{body=JSON}, {continue,send}};
handle_continue(send, S=#state{ack=Ack, nack=_Nack}) ->
    Request = {S#state.uri,[], "application/json", S#state.body},
    try
	httpc:request(post, Request, [{timeout,60000}], [])
    of
	{ok, {{_, Code, _}, _, _}}
	  when Code >= 200, Code < 300 ->
	    Ack(),
	    {stop, normal, S};
	{ok, {{_, Code, Reason},_,_}}
	  when Code >= 300, Code < 500 ->
	    rabbit_log:error("RabbitMQ to 1C plugin. "
			     "Endpoint host return ~p error code."
			     " Message drop. ~nResponse body: ~p"
			     "~nDroped message: ~s",
			     [Code, Reason, S#state.body]),
	    Ack(),
	    {stop, normal, S};
	{ok, {{_, Code, Reason}, _, _}}
	  when Code >= 500, Code < 600 ->
	    rabbit_log:warning("RabbitMQ to 1C plugin. "
			       "Endpoint host return ~p error code with reason ~p."
			       " Message will be resend after 60 seconds",
			       [Code, Reason]),
	    {noreply, S, 60000};
	{error, Reason} ->
	    rabbit_log:error("RabbitMQ to 1C plugin. "
			     "function httpc:request return error: ~p", [Reason]),
	    {noreply, S, 60000}
    catch
	Error -> rabbit_log:error("RabbitMQ to 1C plugin. "
				  "Endpoint worker terminate with error ~p~n"
				  "Msg: ~s", [Error, S#state.body]),
		 {stop, Error, S}
    end.

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

handle_info(timeout, State) ->
    {noreply, State, {continue, send}};
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
make_json(VHost, Queue, {Deliver = #'basic.deliver'{},
			 #amqp_msg{props = Props,
				   payload=Payload}})->
    J1 = add_value(<<"vhost">>, VHost, #{}),
    J2 = add_value(<<"exchange">>, Deliver#'basic.deliver'.exchange, J1),
    J3 = add_value(<<"routing_key">>, Deliver#'basic.deliver'.routing_key, J2),
    J4 = add_value(<<"queue">>, Queue, J3),
    J5 = add_value(<<"content_type">>, Props#'P_basic'.content_type, J4),
    J6 = add_value(<<"content_encoding">>, Props#'P_basic'.content_encoding, J5),
    J7 = add_value(<<"headers">>, parse_headers(Props#'P_basic'.headers), J6),
    J8 = add_value(<<"delivery_mode">>, Props#'P_basic'.delivery_mode, J7),
    J9 = add_value(<<"priority">>, Props#'P_basic'.priority, J8),
    J10 = add_value(<<"correlation_id">>, Props#'P_basic'.correlation_id, J9),
    J11 = add_value(<<"reply_to">>, Props#'P_basic'.reply_to, J10),
    J12 = add_value(<<"expiration">>, Props#'P_basic'.expiration, J11),
    J13 = add_value(<<"message_id">>, Props#'P_basic'.message_id, J12),
    J14 = add_value(<<"timestamp">>, Props#'P_basic'.timestamp, J13),
    J15 = add_value(<<"type">>, Props#'P_basic'.type, J14),
    J16 = add_value(<<"user_id">>, Props#'P_basic'.user_id, J15),
    J17 = add_value(<<"app_id">>, Props#'P_basic'.app_id, J16),
    J18 = add_value(<<"payload">>, Payload, J17),
    J18.

add_value(_, undefined, Acc)->
    Acc;
add_value(Name, Val, Acc) ->
    Acc#{Name => Val}.


parse_headers(Headers) ->
    lists:map(fun parse_header/1, Headers).

parse_array(Array) ->
    Fun = fun ({Type, Val}) ->
		  Value=case Type of
			    array -> parse_array(Val);
			    table -> parse_headers(Val);
			    _ -> Val
			end,
		  #{<<"type">> => Type,
		    <<"value">> => Value}
	  end,
    lists:map(Fun, Array).

parse_header({Name, Type, Val})->
    Value = case Type of
		array -> parse_array(Val);
		table -> parse_headers(Val);
		_ -> Val
	    end,
    #{<<"name">> => Name,
      <<"type">> => Type,
      <<"value">> => Value}.


