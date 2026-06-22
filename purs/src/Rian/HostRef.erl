-module(rian_hostRef@foreign).
-export([refExported/3]).

%% refExported(PartsArray, Erlang, Arity) -> boolean()
%%
%% The host-FFI boundary for `@external` reference-arity resolution (ADR-0068/0041 §2), mirroring
%% Rian.Check.resolve_external_ref: `true` (ok) when the module is unresolvable (a single bare ref,
%% or a module that cannot be loaded — never a false error for a not-yet-loaded module) or the
%% function is exported at `Arity`; `false` ONLY when the module IS loaded but exports no such
%% `fun/arity`. `PartsArray` is a purerl Array (an Erlang `array` of binaries); `Erlang` is the
%% `true`/`false` atom (Erlang `:mod.fun` vs Elixir `Mod.fun`).
refExported(PartsArray, Erlang, Arity) ->
  Parts = array:to_list(PartsArray),
  {Mod, Fun} = ref_mfa(Parts, Erlang),
  case Mod of
    nil -> true;
    _ ->
      case code:ensure_loaded(Mod) of
        {module, Mod} -> erlang:function_exported(Mod, Fun, Arity);
        _ -> true
      end
  end.

%% Mirrors Rian.Check.ref_mfa/2. Atoms are interned (matching the reference's String.to_atom);
%% a name that names no real module simply fails `ensure_loaded` above and yields `true` (ok).
ref_mfa([Single], false) ->
  {nil, binary_to_atom(Single, utf8)};
ref_mfa(Parts, true) ->
  {ModParts, [Fun]} = lists:split(length(Parts) - 1, Parts),
  ModBin = iolist_to_binary(lists:join(<<".">>, ModParts)),
  {binary_to_atom(ModBin, utf8), binary_to_atom(Fun, utf8)};
ref_mfa(Parts, false) ->
  {ModParts, [Fun]} = lists:split(length(Parts) - 1, Parts),
  ModStr = "Elixir." ++ string:join([binary_to_list(P) || P <- ModParts], "."),
  {list_to_atom(ModStr), binary_to_atom(Fun, utf8)}.
