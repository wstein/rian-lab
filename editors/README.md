# Editor support

Editor integrations for the [Rian](../README.md) language. These are tooling
aids only — they do not affect the compiler pipeline.

| Editor             | Path                         | Provides                                       |
| ------------------ | ---------------------------- | ---------------------------------------------- |
| Visual Studio Code | [vscode/rian/](vscode/rian/) | TextMate syntax highlighting for `.rian` files |

The VS Code extension is **highlighting only** (no language server). See its
[README](vscode/rian/README.md) for install and development instructions; it
colours the surface syntax walked by the [`examples/rian/`](../examples/rian/)
tour.
