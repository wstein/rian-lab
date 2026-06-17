%% @doc The `rian` provider: compile every `.rian` source under each app's
%% `rian_src/` directory to a loadable `.beam` in that app's `ebin/`, by shelling
%% out to the toolchain-free `rian build` escript (ADR-0026/0031). Wire it to run
%% on `rebar3 compile` with, in the consuming project's `rebar.config`:
%%
%%   {plugins, [{rebar3_rian, {git, "…", {branch, "main"}}}]}.
%%   {provider_hooks, [{post, [{compile, rian}]}]}.
%%   {rian, [{bin, "rian"}, {src_dir, "rian_src"}]}.   %% both optional (defaults shown)
%%
%% `rian` must be on PATH (or give an absolute path via `{rian, [{bin, …}]}`).
-module(rebar3_rian_prv).

-behaviour(provider).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, rian).
%% run after app discovery so the app dirs / ebin paths are known.
-define(DEPS, [app_discovery]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
        {name, ?PROVIDER},
        {module, ?MODULE},
        {bare, true},
        {deps, ?DEPS},
        {example, "rebar3 rian"},
        {opts, []},
        {short_desc, "Compile Rian (.rian) sources to BEAM"},
        {desc,
            "Compile every .rian under each app's rian_src/ to ebin/ via the `rian` escript. "
            "Configure with {rian, [{bin, \"rian\"}, {src_dir, \"rian_src\"}]}."}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    Bin = cfg(State, bin, "rian"),
    SrcDir = cfg(State, src_dir, "rian_src"),

    Apps =
        case rebar_state:current_app(State) of
            undefined -> rebar_state:project_apps(State);
            App -> [App]
        end,

    try
        lists:foreach(fun(App) -> compile_app(App, Bin, SrcDir) end, Apps),
        {ok, State}
    catch
        throw:{rian_error, Msg} -> {error, format_error(Msg)}
    end.

-spec format_error(any()) -> iolist().
format_error(Reason) when is_list(Reason) -> Reason;
format_error(Reason) -> io_lib:format("~p", [Reason]).

%% ── internals ──────────────────────────────────────────────────────────────

compile_app(App, Bin, SrcDir) ->
    Dir = rebar_app_info:dir(App),
    Ebin = rebar_app_info:ebin_dir(App),
    ok = filelib:ensure_dir(filename:join(Ebin, ".keep")),
    Sources = filelib:wildcard(filename:join([Dir, SrcDir, "*.rian"])),
    [compile_one(Src, Bin, Ebin) || Src <- Sources],
    case Sources of
        [] -> ok;
        _ -> rebar_api:info("Compiled ~p Rian source(s) -> ~ts", [length(Sources), Ebin])
    end.

compile_one(Src, Bin, Ebin) ->
    rebar_api:debug("rian build ~ts -o ~ts", [Src, Ebin]),
    Cmd = lists:flatten(io_lib:format("~ts build ~ts -o ~ts", [Bin, Src, Ebin])),
    case rebar_utils:sh(Cmd, [return_on_error, {use_stdout, false}]) of
        {ok, _Out} ->
            ok;
        {error, {_Code, Out}} ->
            throw({rian_error, io_lib:format("`~ts` failed:~n~ts", [Cmd, Out])})
    end.

cfg(State, Key, Default) ->
    Opts = rebar_state:get(State, rian, []),
    proplists:get_value(Key, Opts, Default).
