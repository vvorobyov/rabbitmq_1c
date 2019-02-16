-module(rabbitmq_1c).
-export([status/0, restart_worker/2]).

status()->
    rabbit_1c_status:status().

restart_worker(dynamic, Name) when is_binary(Name) ->
    rabbit_1c_dyn_worker_sup_sup:restart_child(Name),
    ok;
restart_worker(dynamic, Name0) when is_list(Name0) ->
    Name = erlang:list_to_binary(Name0),
    rabbit_1c_dyn_worker_sup_sup:restart_child(Name),
    ok;
restart_worker(dynamic, Name0) when is_atom(Name0) ->
    Name = erlang:atom_to_binary(Name0, unicode),
    rabbit_1c_dyn_worker_sup_sup:restart_child(Name),
    ok;
restart_worker(dynamic, Name) ->
    io:format("~nIncorrect worker name value: ~p~n",[Name]);
restart_worker(static, Name) when is_atom(Name) ->
    rabbit_1c_worker_sup_sup:restart_child(Name),
    ok;
restart_worker(static, Name0) when is_list(Name0) ->
    Name = erlang:list_to_atom(Name0),
    rabbit_1c_worker_sup_sup:restart_child(Name),
    ok;
restart_worker(static, Name0) when is_binary(Name0) ->
    Name = erlang:binary_to_atom(Name0, unicode),
    rabbit_1c_worker_sup_sup:restart_child(Name),
    ok;
restart_worker(static, Name) ->
    io:format("~nIncorrect worker name value: ~p~n",[Name]);
restart_worker(Type, _) ->
    io:format("~nUndefined type value: ~p~n", [Type]).


    



