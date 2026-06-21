{ name = "rian-purs"
, dependencies = [ "prelude" ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs" ]
, backend = "purerl"
}
