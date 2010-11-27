-module(syslog_server).
-behaviour(gen_server).

%% gen_server callbacks
-export([start_link/0, init/1, handle_call/3, handle_cast/2, 
         handle_info/2, terminate/2, code_change/3]).

-record(state, {socket, key='$end_of_table'}).

%% API functions
start_link() ->
    gen_server2:start_link({local, ?MODULE}, ?MODULE, [], []).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%% @hidden
%%--------------------------------------------------------------------
init([]) ->
    ets:new(?MODULE, [set, named_table, protected]),
    [start_worker() || _ <- lists:seq(1, 100)],
    {ok, Socket} = gen_udp:open(9999, [binary, {active, true}]),
    {ok, #state{socket=Socket}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%% @hidden
%%--------------------------------------------------------------------
handle_call(_Msg, _From, State) ->
    {reply, {error, invalid_call}, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%% @hidden
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%% @hidden
%%--------------------------------------------------------------------
handle_info({udp, Socket, _IP, _InPortNo, Packet}, #state{socket=Socket, key=Prev}=State) ->
    {Pid, Next} = next(Prev),
    logplex_worker:push(Pid, Packet),
    {noreply, State#state{key=Next}};

handle_info({'DOWN', MonitorRef, process, Pid, _Info}, #state{key=Prev}=State) ->
    erlang:demonitor(MonitorRef),
    ets:delete(?MODULE, Pid),
    start_worker(),
    case Prev == Pid of
        true ->
            {noreply, State#state{key='$end_of_table'}};
        false ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%% @hidden
%%--------------------------------------------------------------------
terminate(_Reason, _State) -> 
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%% @hidden
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
start_worker() ->
    {ok, Pid} = logplex_worker:start_link(),
    MonitorRef = erlang:monitor(process, Pid),
    ets:insert(?MODULE, {Pid, MonitorRef}),
    Pid.

next('$end_of_table') ->
    case ets:first(?MODULE) of
        '$end_of_table' -> {undefined, '$end_of_table'};
        Pid -> {Pid, Pid}
    end;

next(Prev) ->
    case ets:next(?MODULE, Prev) of
        '$end_of_table' ->
            case ets:first(?MODULE) of
                '$end_of_table' -> {undefined, '$end_of_table'};
                Pid -> {Pid, Pid}
            end;
        Pid ->
            {Pid, Pid}
    end.