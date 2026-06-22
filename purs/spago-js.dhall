-- The JS-backend build profile (ADR-0090) — compiles the PureScript port to JavaScript via stock
-- `purs` (its native backend), toward the in-browser playground compiler. Same `src/**/*.purs` as
-- the purerl build (`spago.dhall`), but:
--   * NO `backend` field → `purs`'s default JS code generator (not purerl/Erlang);
--   * the standard JS package set (`packages-js.dhall`), not the purerl dhall set;
--   * `HostRef` resolves through `HostRef.js` (the conservative-accept stub), not `HostRef.erl`.
-- Build + smoke-test with `scripts/js-build.sh`.
{ name = "rian-purs-js"
, dependencies =
  [ "prelude", "arrays", "control", "enums", "either", "foldable-traversable"
  , "integers", "lists", "maybe", "numbers", "partial", "strings", "tuples"
  ]
, packages = ./packages-js.dhall
, sources = [ "src/**/*.purs" ]
}
