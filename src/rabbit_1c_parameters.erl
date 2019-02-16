%%%-------------------------------------------------------------------
%%% @author Vladislav Vorobyov <vlad@erldev>
%%% @copyright (C) 2019, Vladislav Vorobyov
%%% @doc
%%%
%%% @end
%%% Created : 14 Feb 2019 by Vladislav Vorobyov <vlad@erldev>
%%%-------------------------------------------------------------------
-module(rabbit_1c_parameters).
-behaviour(rabbit_runtime_parameter).
%% API
-export([register/0, unregister/0]).
%% Callbacks
-export([validate/5, notify/5, notify_clear/4]).

-rabbit_boot_step({?MODULE,
		   [{destination, "RabbitMQ to 1C plugin"},
		    {mfa, {rabbit_1c_parameters, register, []}},
		    {cleanup, {?MODULE, unregister, []}},
		    {requires, rabbit_registry},
		    {enables, recovery}]}).
%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Register dinamyc parameters module
%% @spec
%% @end
%%--------------------------------------------------------------------
register()->
    rabbit_registry:register(
      runtime_parameter, <<"rabbitmq_1c">>, ?MODULE).

%%--------------------------------------------------------------------
%% @doc
%% Unregister dinamyc parameters module
%% @spec
%% @end
%%--------------------------------------------------------------------
unregister()->
    rabbit_registry:unregister(
      runtime_parameter, <<"rabbitmq_1c">>).


%%%===================================================================
%%% Callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Validate dinamyc parameter
%% @spec
%% @end
%%--------------------------------------------------------------------
validate(_VHost, <<"rabbitmq_1c">>, Name, Def0, _User)->
    Def = rabbit_data_coercion:to_proplist(Def0),
    rabbit_1c_config:validate_config(dynamic, Name, Def);
validate(_VHost, _Component, Name, _Term, _User) ->
    {error, "name not recognised: ~p", [Name]}.


%%--------------------------------------------------------------------
%% @doc
%% Start dinamyc worker
%% @spec
%% @end
%%--------------------------------------------------------------------
notify(_VHost, <<"rabbitmq_1c">>, Name, Def, _User)->
    rabbit_1c_dyn_worker_sup_sup:adjust(Name, Def).
%%--------------------------------------------------------------------
%% @doc
%% Stop dinamyc worker
%% @spec
%% @end
%%--------------------------------------------------------------------
notify_clear(_VHost, <<"rabbitmq_1c">>, Name, _User)->
    rabbit_1c_dyn_worker_sup_sup:stop_child(Name).

%%%===================================================================
%%% Internal functions
%%%===================================================================
