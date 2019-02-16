%%%-------------------------------------------------------------------
%%% @author Vladislav Vorobyov <vlad@erldev>
%%% @copyright (C) 2019, Vladislav Vorobyov
%%% @doc
%%%
%%% @end
%%% Created : 11 Feb 2019 by Vladislav Vorobyov <vlad@erldev>
%%%-------------------------------------------------------------------
-module(rabbit_1c_config).

%% API
-export([parse_configuration/0, parse_config/3, validate_config/3]).

-import(rabbit_misc, [pget/2, pget/3]).
%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
parse_configuration() ->
    try
	parse_static_configs()
    catch
	{error, Str, Args} ->
	    {error, {Str, Args}}
    end.
parse_config(static, Name, Config)->
    Validate = validate_config(static, Name, Config),
    Fun = fun (ok)-> ok;
	      ({error, Str, Param}) ->
		  throw({error, Str, Param})
	  end,
    lists:map(Fun, Validate),
    RecDelay = pget(reconnect_delay, Config, 60),
    AckMode = pget(ack_mode, Config, on_confirm),
    SrcUri = pget(source, Config),
    Queue = pget(queue, Config),
    DestUri = pget(destination, Config),
    {Name, #{reconnect_delay => RecDelay,
	     type => static,
	     ack_mode => AckMode,
	     source => SrcUri,
	     queue => Queue,
	     dest => DestUri}};
parse_config(dynamic, Name, Config) ->
    RecDelay = pget(<<"reconnect-delay">>, Config, 60),
    AckMode = translate_ack_mode(pget(<<"ack-mode">>, Config, <<"on-confirm">>)),
    SrcUri = erlang:binary_to_list(pget(<<"src-uri">>, Config)),
    Queue = pget(<<"src-queue">>, Config),
    DestUri = erlang:binary_to_list(pget(<<"dst-uri">>, Config)),
    {Name, #{reconnect_delay => RecDelay,
	     type => dynamic,
	     ack_mode => AckMode,
	     source => SrcUri,
	     queue => Queue,
	     dest => DestUri}}.
    
validate_config(Type, Name, Config)->
    Validations = get_validations(Type),
    rabbit_parameter_validation:proplist(Name, Validations, Config).

    
%%%===================================================================
%%% Internal functions
%%%===================================================================
parse_static_configs() ->
    Def = application:get_env(rabbitmq_1c,webshovels, []),
    validate(Def),
    Config = lists:map(fun ({Name, Config}) ->
			       parse_config(static, Name, Config) end, Def),
    {ok,maps:from_list(Config)}.

validate(Props) ->
    validate_proplist(Props),
    validate_duplicates(Props).

validate_proplist(Props) when is_list (Props) ->
    case lists:filter(fun ({_, _}) -> false;
                          (_) -> true
                      end, Props) of
        [] -> ok;
        Invalid ->
            throw({error, "invalid parameters: ~p", Invalid})
    end;
validate_proplist(X) ->
    throw({error, "require_list: ~p", X}).
    
validate_duplicates(Props) ->
    case duplicate_keys(Props) of
        [] -> ok;
        Invalid ->
            throw({error, "duplicate parameters: ~p", Invalid})
    end.

duplicate_keys(PropList) when is_list(PropList) ->
    proplists:get_keys(
      lists:foldl(fun (K, L) -> lists:keydelete(K, 1, L) end, PropList,
                  proplists:get_keys(PropList))).


get_validations(dynamic)->
    [{<<"reconnect-delay">>, fun rabbit_parameter_validation:number/2, optional},
     {<<"ack-mode">>, rabbit_parameter_validation:enum(
			['no-ack', 'on-publish', 'on-confirm']), optional},
     {<<"src-uri">>, fun validate_amqp_uri/2, mandatory},
     {<<"src-queue">>, fun rabbit_parameter_validation:binary/2, mandatory},
     {<<"dst-uri">>, fun validate_http_uri/2, mandatory}];
get_validations(static)->
    [{reconnect_delay, fun rabbit_parameter_validation:number/2, optional},
     {ack_mode, rabbit_parameter_validation:enum(
			[no_ack, on_publish, on_confirm]), optional},
     {source, fun validate_amqp_uri/2, mandatory},
     {queue, fun rabbit_parameter_validation:binary/2, mandatory},
     {destination, fun validate_http_uri/2, mandatory}].


validate_http_uri(Name, Term) when is_list(Term) ->
    validate_http_uri(Name, erlang:list_to_binary(Term) );
validate_http_uri(Name, Term) ->
    case rabbit_parameter_validation:binary(Name, Term) of
	ok -> case http_uri:parse(Term) of
		  {ok, _} -> ok;
		  {error, Err} -> {error, "\"~s\" not a valid HTTP URI: ~p", [Term, Err]}
	      end;
	E -> E
    end.

validate_amqp_uri(Name, Term) when is_list(Term) ->
    validate_amqp_uri(Name, erlang:list_to_binary(Term) );
validate_amqp_uri(Name, Term)->
    case rabbit_parameter_validation:binary(Name, Term) of
	ok -> case amqp_uri:parse(Term) of
		  {ok, _} -> ok;
		  {error, Err} -> {error, "\"~s\" not a valid AMQP URI: ~p",
				   [Term, Err]}
	      end;
	E -> E
    end.

translate_ack_mode(<<"on-confirm">>) -> on_confirm;
translate_ack_mode(<<"on-publish">>) -> on_publish;
translate_ack_mode(<<"no-ack">>)     -> no_ack.
