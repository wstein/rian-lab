# Dialyzer warnings to suppress (genuine false positives only — `mix dialyzer`).
# Entries are {"path/file.ex", :warning_type}. Keep the list short and commented.
# `list_unused_filters: true` (in mix.exs) fails the run if an entry stops
# matching, so stale ignores can't accumulate.
[
  # MapSet is `@opaque`. The constant-resolution context stores its `cset` MapSet
  # in a plain map and reads it back via `MapSet.member?/2`; Dialyzer loses the
  # opacity tag across the map boundary and reports a spurious opacity mismatch.
  # The set is only ever built/queried through `MapSet.*`, so this is a false
  # positive (a well-known wart with opaque types held in maps).
  {"lib/rian/lower.ex", :call_with_opaque},
  {"lib/rian/lower.ex", :call_without_opaque},

  # The same MapSet-in-a-map wart in `Rian.Optimize`: the post-check inliner threads its
  # `inlining` MapSet inside the `ctx` map and queries it via `MapSet.member?/2`; Dialyzer
  # loses the opacity tag across the map boundary at the `inline_const_calls/2` call. False
  # positive — the set is only ever built/read through `MapSet.*` (ADR-0046 §5).
  {"lib/rian/optimize.ex", :call_with_opaque},

  # Dev-only documentation tooling (`Rian.DocFormatter`, a `mix docs` formatter)
  # drives ExDoc's *internal* API (`ExDoc.DocAST.extract_title/map_tags/text`,
  # `ExDoc.version`), which Dialyzer can't see among ExDoc's published exports.
  # These run under `mix docs`, are not part of the compiler, and not unit-tested.
  {"dev/rian/doc_formatter.ex", :unknown_function},
  {"dev/rian/doc_formatter/mdx.ex", :unknown_function}
]
