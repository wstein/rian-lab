-module(rian_beam@foreign).

%% The Erlang-FFI boundary for the abstract-forms BEAM backend (ADR-0031 / ADR-0084 Phase 8).
%% Rian.Beam builds the Erlang **abstract format** (nested tuples/atoms/integers) as an opaque
%% `ETerm` tree using the small constructor set below, then `runMainImpl` runs it through
%% `compile:forms/2` → `code:load_binary/3` → `Mod:main()`. The bulk (the forms construction) is
%% pure PureScript over `ETerm`; this module is only the term primitives + the compile/load/run tail.
%%
%% purerl represents a PureScript `Array a` as an Erlang `array` (see Rian.HostRef), so the
%% Array-taking builders convert with `array:to_list/1`.
-export([mkAtomTerm/1, mkIntStr/1, mkIntI/1, mkFloatStr/1, mkBinary/1, mkTuple/1, mkList/1,
         runMainImpl/2]).

%% ── ETerm constructors (raw Erlang terms; the abstract-format nodes are tuples of these) ──
mkAtomTerm(B) -> binary_to_atom(B, utf8).      %% a raw atom (module / op / function name)
mkIntStr(B) -> binary_to_integer(B).           %% a raw integer from a Rian numeric string
mkIntI(N) -> N.                                %% a raw integer from a PureScript Int (arity / line)
mkFloatStr(B) -> binary_to_float(B).           %% a raw float
mkBinary(B) -> B.                              %% a raw binary (a Rian String literal)
mkTuple(Arr) -> list_to_tuple(array:to_list(Arr)).
mkList(Arr) -> array:to_list(Arr).

%% ── compile the forms → load → run `main/0` → stringify the result ──
%% `Forms` arrives already as an Erlang list (built via `mkList`). Returns a binary: either the
%% `~p`-rendered result of `Mod:main()`, or a `compile_error:`/`crash:` diagnostic (so a failure is
%% a comparable string under the parity harness, never an exception).
runMainImpl(Forms, ModB) ->
  Mod = binary_to_atom(ModB, utf8),
  try
    case compile:forms(Forms, [return_errors]) of
      {ok, Mod, Bin} -> run(Mod, Bin);
      {ok, Mod, Bin, _Warnings} -> run(Mod, Bin);
      Other -> fmt("compile_error: ~p", [Other])
    end
  catch
    Class:Reason -> fmt("crash: ~p:~p", [Class, Reason])
  end.

run(Mod, Bin) ->
  code:purge(Mod),
  {module, Mod} = code:load_binary(Mod, atom_to_list(Mod) ++ ".beam", Bin),
  Result = Mod:main(),
  fmt("~p", [Result]).

fmt(Format, Args) -> list_to_binary(lists:flatten(io_lib:format(Format, Args))).
