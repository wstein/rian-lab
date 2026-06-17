%% @doc rebar3 plugin entry point — registers the `rian` provider so a rebar3
%% project can compile `.rian` sources to BEAM (ADR-0026 "Erlang citizen").
-module(rebar3_rian).

-export([init/1]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    rebar3_rian_prv:init(State).
