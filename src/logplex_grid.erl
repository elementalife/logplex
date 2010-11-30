%% Copyright (c) 2010 Jacob Vorreuter <jacob.vorreuter@gmail.com>
%% 
%% Permission is hereby granted, free of charge, to any person
%% obtaining a copy of this software and associated documentation
%% files (the "Software"), to deal in the Software without
%% restriction, including without limitation the rights to use,
%% copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the
%% Software is furnished to do so, subject to the following
%% conditions:
%% 
%% The above copyright notice and this permission notice shall be
%% included in all copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
%% HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
%% WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
%% OTHER DEALINGS IN THE SOFTWARE.
-module(logplex_grid).
-export([start_link/0, init/1, publish/2, loop/0]).

start_link() ->
    proc_lib:start_link(?MODULE, init, [self()]).

init(Parent) ->
    proc_lib:init_ack(Parent, {ok, self()}),
    loop().

publish(RegName, Msg) when is_atom(RegName), is_tuple(Msg) ->
    [erlang:send({RegName, Node}, Msg) || Node <- [node()|nodes()]],
    ok.

loop() ->
    redis_helper:set_node_ex(atom_to_binary(node(), utf8), local_ip()),
    case redis_helper:get_nodes() of
        Keys when is_list(Keys) ->
            [connect(Key) || {ok, Key} <- Keys];
        _Err ->
            ok
    end,
    receive
        {nodedown, _Node} ->
            ok
    after 0 ->
        ok
    end,
    timer:sleep(5 * 1000),
    ?MODULE:loop().

local_ip() ->
    case os:getenv("LOCAL_IP") of
        false -> <<"127.0.0.1">>;
        LocalIp -> list_to_binary(LocalIp)
    end.

connect(<<"node:", BinNode/binary>> = Key) ->
    StrNode = binary_to_list(BinNode),
    Node = list_to_atom(StrNode),
    case node() == Node of
        true ->
            undefined;
        false ->
            case net_adm:ping(Node) of
                pong -> ok;
                pang ->
                    case redis_helper:get_node(Key) of
                        {ok, Ip} when is_binary(Ip) ->
                            {ok, Addr} = inet:getaddr(binary_to_list(Ip), inet),
                            case re:run(StrNode, ".*@(.*)$", [{capture, all_but_first, list}]) of
                                {match, [Host]} ->
                                    %io:format("add host ~p -> ~p~n", [Host, Addr]),
                                    inet_db:add_host(Addr, [Host]),
                                    case net_adm:ping(Node) of
                                        pong ->
                                            erlang:monitor_node(Node, true);
                                        pang ->
                                            {error, {ping_failed, Node}}
                                    end;
                                _ ->
                                    {error, {failed_to_parse_host, StrNode}}
                            end;
                        _ ->
                            undefined
                    end
            end
    end.
