# Rian Language Syntax (VS Code)

Syntax highlighting for the [Rian](../../../README.md) programming language,
driven by a TextMate grammar. It colours the surface syntax exercised by the
[`examples/rian/`](../../../examples/rian/) tour: declarations (`def` / `type` /
`struct` / `alias` / `range` / `mod` / `abstract` / `opaque`), reference
capabilities (`val` / `iso` / `ref` / `tag`), `forall` generics and `to`
cast-methods, `case`/`when` matching, word and symbolic operators, atoms,
annotations (`@wire` / `@targets`), the reserved `Prim.*` intrinsic namespace,
and numeric/char/string literals — including `${expr}` interpolation holes
(ADR-0069), whose bodies are highlighted as real source.

This extension is **highlighting only** — there is no language server, so no
completion, diagnostics, or go-to-definition.

## Contents

| Path                            | Purpose                                                       |
| ------------------------------- | ------------------------------------------------------------- |
| `package.json`                  | Extension manifest: registers the `rian` language and grammar |
| `language-configuration.json`   | Comments, brackets, auto-closing, indentation                 |
| `syntaxes/rian.tmLanguage.json` | The TextMate grammar (`source.rian`)                          |
| `tests/`                        | Grammar assertion tests (`vscode-tmgrammar-test`)             |

## Install

From this directory:

```sh
# Load the unpacked extension directly into VS Code:
ln -s "$PWD" ~/.vscode/extensions/rian-syntax

# …or build a .vsix and install it:
npm install
npm run package          # produces rian-syntax-<version>.vsix
code --install-extension rian-syntax-*.vsix
```

Reload VS Code (`Developer: Reload Window`) and open any `.rian` file.

## Develop

```sh
npm install      # dev tooling: vscode-tmgrammar-test, prettier
npm test         # run grammar assertion tests
npm run lint     # check JSON/Markdown formatting (prettier --check)
npm run format   # apply formatting
```

Grammar scopes are asserted inline in `tests/*.rian` using
`vscode-tmgrammar-test` comment annotations, so a regression in the grammar
fails CI rather than silently mis-colouring code.
