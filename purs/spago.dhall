{ name = "rian-purs"
, dependencies =
  [ "prelude", "arrays", "control", "enums", "either", "foldable-traversable"
  , "integers", "lists", "maybe", "numbers", "partial", "strings", "tuples"
  ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs" ]
, backend = "purerl"
}
