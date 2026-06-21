{ name = "rian-purs"
, dependencies =
  [ "prelude", "arrays", "control", "enums", "foldable-traversable"
  , "integers", "lists", "maybe", "partial", "strings", "tuples"
  ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs" ]
, backend = "purerl"
}
