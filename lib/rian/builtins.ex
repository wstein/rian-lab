defmodule Rian.Builtins do
  @moduledoc """
  Declared signatures for **host-runtime foreign functions** (ADR-0068 FFI) — the
  Erlang/Elixir stdlib calls the Elixir→Rian transpiler emits verbatim because they
  have no portable Rian-prelude form. This is the FFI-header analogue: an `extern`
  table that lets `Rian.Check` *type* a foreign call (so e.g. a `${:erlang.phash2(x)}`
  interpolation hole resolves to `Int53` instead of erroring `no Show for unknown`),
  and lets `Rian.Reach` pin any function that calls one to `:ex` (these are host, not
  portable).

  Scope and honesty (the [[feedback-reach-matrix-honesty]] bar):

  * Only functions with a **concrete** return type are listed. A generic-returning
    host call (`Map.keys/1`, `Enum.map/2`, `Regex.run/2`) is deliberately ABSENT —
    its result stays `:unknown`, which is sound (we will not invent a `Vec(_)` it
    can't honestly carry).
  * These are **host (`:ex`-only)** signatures, not a claim that Rian "knows" the
    Elixir stdlib. Portable list/dict/string ops are written in Rian (the prelude,
    `examples/rian/prelude_*.rian`) and resolve through the program, not here.

  Keyed by `{module, fun, arity}`, where `module` is the call's head name string
  (`"String"`, `"Map"`, an Erlang BIF module `"erlang"`/`"file"`/`"math"`), or `nil`
  for an auto-imported `Kernel` call (`map_size/1`, `inspect/1`).
  """
  use Rian.Ann

  # {module | nil, fun, arity} => Rian return type. Concrete returns only.
  @table %{
    # ── Kernel auto-imports (bare calls) ──────────────────────────────────────
    {nil, "map_size", 1} => "Int53",
    {nil, "tuple_size", 1} => "Int53",
    {nil, "byte_size", 1} => "Int53",
    {nil, "bit_size", 1} => "Int53",
    {nil, "inspect", 1} => "String",
    {nil, "inspect", 2} => "String",
    {nil, "to_string", 1} => "String",
    {nil, "is_atom", 1} => "Bool",
    {nil, "is_binary", 1} => "Bool",
    {nil, "is_list", 1} => "Bool",
    {nil, "is_map", 1} => "Bool",
    {nil, "is_tuple", 1} => "Bool",
    {nil, "is_integer", 1} => "Bool",
    {nil, "is_number", 1} => "Bool",
    {nil, "is_nil", 1} => "Bool",

    # ── String (host; not yet covered by the Str prelude) ─────────────────────
    {"String", "replace", 3} => "String",
    {"String", "replace", 4} => "String",
    {"String", "trim", 1} => "String",
    {"String", "trim", 2} => "String",
    {"String", "trim_leading", 2} => "String",
    {"String", "trim_trailing", 2} => "String",
    {"String", "upcase", 1} => "String",
    {"String", "downcase", 1} => "String",
    {"String", "capitalize", 1} => "String",
    {"String", "slice", 2} => "String",
    {"String", "slice", 3} => "String",
    {"String", "duplicate", 2} => "String",
    {"String", "pad_leading", 2} => "String",
    {"String", "pad_trailing", 2} => "String",
    {"String", "first", 1} => "String",
    {"String", "last", 1} => "String",
    {"String", "reverse", 1} => "String",
    {"String", "length", 1} => "Int53",
    {"String", "to_atom", 1} => "Symbol",
    {"String", "to_existing_atom", 1} => "Symbol",
    # arbitrary-precision: the parsed value is unbounded (`Int`, BEAM bignum / JS BigInt),
    # not the 53-bit `Int53` — claiming Int53 would assert a bound the value need not honour.
    {"String", "to_integer", 1} => "Int",
    {"String", "to_integer", 2} => "Int",
    {"String", "split", 2} => "Vec(String)",
    {"String", "split", 3} => "Vec(String)",
    {"String", "contains?", 2} => "Bool",
    {"String", "starts_with?", 2} => "Bool",
    {"String", "ends_with?", 2} => "Bool",
    {"String", "match?", 2} => "Bool",

    # ── Map (host; Dict prelude covers get/put, not these) ────────────────────
    {"Map", "has_key?", 2} => "Bool",

    # ── Enum (host; concrete returns only) ────────────────────────────────────
    {"Enum", "count", 1} => "Int53",
    {"Enum", "member?", 2} => "Bool",
    {"Enum", "any?", 1} => "Bool",
    {"Enum", "all?", 1} => "Bool",
    {"Enum", "empty?", 1} => "Bool",
    {"Enum", "join", 2} => "String",
    {"Enum", "map_join", 3} => "String",

    # ── Integer / Float / Atom → String ───────────────────────────────────────
    {"Integer", "to_string", 1} => "String",
    {"Integer", "to_string", 2} => "String",
    {"Float", "to_string", 1} => "String",
    {"Atom", "to_string", 1} => "String",

    # ── Regex (host) ──────────────────────────────────────────────────────────
    {"Regex", "escape", 1} => "String",
    {"Regex", "match?", 2} => "Bool",
    {"Regex", "replace", 3} => "String",
    {"Regex", "replace", 4} => "String",

    # ── Path (host) ───────────────────────────────────────────────────────────
    {"Path", "join", 1} => "String",
    {"Path", "join", 2} => "String",
    {"Path", "expand", 1} => "String",
    {"Path", "expand", 2} => "String",
    {"Path", "basename", 1} => "String",
    {"Path", "dirname", 1} => "String",
    {"Path", "extname", 1} => "String",
    {"Path", "relative_to", 2} => "String",
    {"Path", "relative_to_cwd", 1} => "String",

    # ── IO (host effect) ──────────────────────────────────────────────────────
    {"IO", "puts", 1} => "Symbol",
    {"IO", "puts", 2} => "Symbol",
    {"IO", "write", 1} => "Symbol",

    # ── Erlang BIFs (`:erlang.*` etc.) ────────────────────────────────────────
    {"erlang", "phash2", 1} => "Int53",
    {"erlang", "phash2", 2} => "Int53",
    {"erlang", "integer_to_binary", 1} => "String",
    {"erlang", "integer_to_binary", 2} => "String",
    {"erlang", "float_to_binary", 1} => "String",
    {"erlang", "float_to_binary", 2} => "String",
    {"erlang", "atom_to_binary", 1} => "String",
    {"erlang", "atom_to_binary", 2} => "String",
    {"erlang", "binary_to_atom", 1} => "Symbol",
    {"erlang", "binary_to_atom", 2} => "Symbol",
    # arbitrary-precision / unbounded: a parsed bignum, a possibly-negative unbounded
    # unique int, and a nanosecond epoch (~2^60) all exceed `Int53` — type as `Int`.
    {"erlang", "binary_to_integer", 1} => "Int",
    {"erlang", "unique_integer", 0} => "Int",
    {"erlang", "unique_integer", 1} => "Int",
    {"erlang", "system_time", 0} => "Int",
    {"erlang", "system_time", 1} => "Int",
    {"file", "format_error", 1} => "String",
    {"math", "pi", 0} => "Float64",
    {"math", "sqrt", 1} => "Float64",
    {"math", "pow", 2} => "Float64"
  }

  # Fixed-head **polymorphic** host/stdlib signatures (ADR-0050, ADR-0047): functions
  # whose return *head* is a contract — `List.reverse` always yields a `Vec`, `Map.put`
  # a `Dict` — even when the element type can't be pinned. `{params, ret, tvars}`; the
  # caller (`Rian.Check`) instantiates the tvars from the inferred argument types and
  # fills any it can't bind with a `_Unk` hole (so `List.reverse(unknown)` → `Vec(_Unk)`,
  # not `:unknown`). Distinct from `@table`, which is *concrete* returns only — here the
  # head is justified by the function's contract, the element deferred. Reach pins the
  # host ones (`Enum.*`, `Map.*`) off non-BEAM independently, so this only types the call.
  @poly %{
    {"List", "reverse", 1} => {["Vec(T)"], "Vec(T)", ["T"]},
    {"List", "map", 2} => {["Vec(T)", "Fn(T,U)"], "Vec(U)", ["T", "U"]},
    {"List", "filter", 2} => {["Vec(T)", "Fn(T,Bool)"], "Vec(T)", ["T"]},
    {"List", "reject", 2} => {["Vec(T)", "Fn(T,Bool)"], "Vec(T)", ["T"]},
    {"List", "flat_map", 2} => {["Vec(T)", "Fn(T,Vec(U))"], "Vec(U)", ["T", "U"]},
    {"List", "concat", 2} => {["Vec(T)", "Vec(T)"], "Vec(T)", ["T"]},
    {"List", "take", 2} => {["Vec(T)", "Int53"], "Vec(T)", ["T"]},
    {"List", "drop", 2} => {["Vec(T)", "Int53"], "Vec(T)", ["T"]},
    {"List", "sort", 1} => {["Vec(T)"], "Vec(T)", ["T"]},
    {"List", "uniq", 1} => {["Vec(T)"], "Vec(T)", ["T"]},
    {"Enum", "map", 2} => {["Vec(T)", "Fn(T,U)"], "Vec(U)", ["T", "U"]},
    {"Enum", "filter", 2} => {["Vec(T)", "Fn(T,Bool)"], "Vec(T)", ["T"]},
    {"Enum", "reject", 2} => {["Vec(T)", "Fn(T,Bool)"], "Vec(T)", ["T"]},
    {"Enum", "uniq", 1} => {["Vec(T)"], "Vec(T)", ["T"]},
    {"Enum", "reverse", 1} => {["Vec(T)"], "Vec(T)", ["T"]},
    {"Enum", "sort", 1} => {["Vec(T)"], "Vec(T)", ["T"]},
    {"Enum", "to_list", 1} => {["Vec(T)"], "Vec(T)", ["T"]},
    {"Map", "new", 0} => {[], "Dict(_Unk,_Unk)", []},
    {"Map", "new", 1} => {["Vec(T)"], "Dict(_Unk,_Unk)", ["T"]},
    {"Map", "new", 2} => {["Vec(T)", "Fn(T,U)"], "Dict(_Unk,_Unk)", ["T", "U"]},
    {"Map", "put", 3} => {["Dict(K,V)", "K", "V"], "Dict(K,V)", ["K", "V"]},
    {"Map", "delete", 2} => {["Dict(K,V)", "K"], "Dict(K,V)", ["K", "V"]},
    {"Map", "update", 4} => {["Dict(K,V)", "K", "V", "Fn(V,V)"], "Dict(K,V)", ["K", "V"]},
    {"Map", "merge", 2} => {["Dict(K,V)", "Dict(K,V)"], "Dict(K,V)", ["K", "V"]}
  }

  @rian_sig "pub def poly_sig(module Option(String), fun String, arity Int53) Option((Vec(String), String, Vec(String)))"
  @doc """
  The fixed-head polymorphic signature `{params, ret, tvars}` of a host/stdlib function,
  or `nil`. The caller instantiates the tvars from argument types (`_Unk` when unbound).
  """
  @spec poly_sig(String.t() | nil, String.t(), non_neg_integer()) ::
          {[String.t()], String.t(), [String.t()]} | nil
  def poly_sig(module, fun, arity), do: Map.get(@poly, {module, fun, arity})

  @rian_sig "pub def ret(module Option(String), fun String, arity Int53) Option(String)"
  @doc """
  The declared Rian return type of a host foreign function, or `nil` if it is not a
  known builtin (or has no concrete return — the caller then treats it as `:unknown`).
  `module` is the call head name (`"String"`, `"erlang"`, …) or `nil` for a `Kernel`
  auto-import.
  """
  @spec ret(String.t() | nil, String.t(), non_neg_integer()) :: String.t() | nil
  def ret(module, fun, arity), do: Map.get(@table, {module, fun, arity})

  @rian_sig "pub def known?(module Option(String), fun String, arity Int53) Bool"
  @doc "Whether `{module, fun, arity}` is a registered host builtin."
  @spec known?(String.t() | nil, String.t(), non_neg_integer()) :: boolean()
  def known?(module, fun, arity), do: Map.has_key?(@table, {module, fun, arity})
end
