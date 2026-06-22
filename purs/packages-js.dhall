-- The standard (JavaScript) PureScript package set for the JS-backend build (ADR-0090) — the
-- in-browser playground compiler. The purerl build uses `packages.dhall` (the purerl/package-sets
-- *dhall* set, Erlang FFI); this is its JS-backend twin: the same core libraries with their native
-- JS FFI, from the official purescript/package-sets set for the pinned purs 0.15.x.
let upstream =
      https://github.com/purescript/package-sets/releases/download/psc-0.15.15-20260615/packages.dhall
        sha256:1ff433c687409ab366a1a292366fa25d74dc8a17679fef0368e161a8e2c4cc9a

in  upstream
