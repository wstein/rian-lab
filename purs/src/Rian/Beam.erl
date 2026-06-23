-module(rian_beam@foreign).

%% The Erlang-FFI boundary for the abstract-forms BEAM backend (ADR-0031 / ADR-0084 Phase 8).
%% Rian.Beam builds the Erlang **abstract format** (nested tuples/atoms/integers) as an opaque
%% `ETerm` tree using the small constructor set below, then `runMainImpl` runs it through
%% `compile:forms/2` → `code:load_binary/3` → `Mod:main()`. The bulk (the forms construction) is
%% pure PureScript over `ETerm`; this module is only the term primitives + the compile/load/run tail.
%%
%% purerl represents a PureScript `Array a` as an Erlang `array` (see Rian.HostRef), so the
%% Array-taking builders convert with `array:to_list/1`.
-export([mkAtomTerm/1, mkIntStr/1, mkIntI/1, mkFloatStr/1, mkBinary/1, strBytes/1, mkTuple/1,
         mkList/1, runModulesImpl/3]).

%% ── ETerm constructors (raw Erlang terms; the abstract-format nodes are tuples of these) ──
mkAtomTerm(B) -> binary_to_atom(B, utf8).      %% a raw atom (module / op / function name)
mkIntStr(B) -> binary_to_integer(B).           %% a raw integer from a Rian numeric string
mkIntI(N) -> N.                                %% a raw integer from a PureScript Int (arity / line)
mkFloatStr(B) -> binary_to_float(B).           %% a raw float
mkBinary(B) -> B.                              %% a raw binary (a Rian String literal)
strBytes(B) -> binary_to_list(B).              %% the UTF-8 byte charlist of a String (a `{string,…}` node)
mkTuple(Arr) -> list_to_tuple(array:to_list(Arr)).
mkList(Arr) -> array:to_list(Arr).

%% ── compile each module's forms → load all → run the main module's `main/0` → stringify ──
%% `ModsArr` is a PureScript `Array` (an Erlang `array`) of module-forms, each already an Erlang
%% list (built via `mkList`); `MainB` names the module to run. Aux modules (e.g. the injected `Show`
%% for `${float}`, or sibling `mod`s) are compiled + loaded first, so a cross-module call from the
%% main module resolves. Returns a binary: the `~p`-rendered result of `Main:main()`, or a
%% `compile_error:`/`crash:` diagnostic (a comparable string under parity, never an exception).
runModulesImpl(PreludeArr, ModsArr, MainB) ->
  Main = binary_to_atom(MainB, utf8),
  try
    ensure_prelude(array:to_list(PreludeArr)),
    lists:foreach(fun load_forms/1, array:to_list(ModsArr)),
    fmt("~p", [Main:main()])
  catch
    throw:{compile_error, Err} -> fmt("compile_error: ~p", [Err]);
    Class:Reason -> fmt("crash: ~p:~p", [Class, Reason])
  end.

%% Compile + load the portable-prelude modules ONCE per VM (idempotent): if the sentinel
%% `Elixir.Rian.Prelude.List` is already loaded, every prelude module is, so skip the (Erlang-)
%% compiler work on every subsequent program. Mirrors `Rian.Prelude.load/0`.
ensure_prelude(Forms) ->
  case code:is_loaded('Elixir.Rian.Prelude.List') of
    false -> lists:foreach(fun load_forms/1, Forms);
    _ -> ok
  end.

load_forms(Forms) ->
  case compile:forms(Forms, [return_errors]) of
    {ok, Mod, Bin} -> do_load(Mod, Bin);
    {ok, Mod, Bin, _Warnings} -> do_load(Mod, Bin);
    Other -> throw({compile_error, Other})
  end.

do_load(Mod, Bin) ->
  code:purge(Mod),
  {module, Mod} = code:load_binary(Mod, atom_to_list(Mod) ++ ".beam", Bin),
  ok.

fmt(Format, Args) -> list_to_binary(lists:flatten(io_lib:format(Format, Args))).
