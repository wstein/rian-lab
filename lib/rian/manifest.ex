defmodule Rian.Manifest do
  @moduledoc """
  Reader for `rian.toml` — the declarative project manifest (ADR-0080 §2), the
  **single source** of project metadata that every Rian tool reads (never inferring
  from the tree). The foundation of the build system: `rian build`/`test`/`run`, the
  foreign-file resolver (ADR-0080 §7), and the Hex/Cargo/npm packaging layer
  (ADR-0026) all consume it; `Rian.Reach` reads its `targets` as the portability
  contract (ADR-0058).

  This parses the **constrained TOML subset** the manifest uses — `[table]` headers,
  `key = "string"`, `key = ["string", …]` arrays, `#` comments — deliberately *not* a
  general TOML parser, to keep the compiler's zero-runtime-dependency posture. A value
  shape outside the subset is a clear error rather than a silent misread: strings carry
  no escape sequences (so an embedded `"` is malformed, not a truncation), and a comma
  *inside* a quoted array value is preserved rather than split on.

  ```toml
  [project]
  name    = "my_app"
  version = "0.1.0"
  kind    = "app"            # "app" | "lib"
  license = "Apache-2.0"
  authors = ["Ada Lovelace <ada@example.com>"]
  targets = ["ex", "rs", "js"]

  [deps]
  some_lib = "1.0"

  [lint]
  max_severity = "warn"
  ```
  """

  use Rian.Ann
  alias Rian.Reach

  @rian_sig """
  struct Manifest(name String, version String, kind String, license Option(String),
                  authors Vec(String), targets Vec(Symbol),
                  deps Dict(String, String), lint Dict(String, String))
  """
  @enforce_keys [:name, :version]
  defstruct name: nil,
            version: nil,
            kind: "lib",
            license: nil,
            authors: [],
            targets: [],
            deps: %{},
            lint: %{}

  @type t :: %__MODULE__{}

  @kinds ~w(app lib)

  @doc """
  Read and parse the manifest at `path` (default `rian.toml`). Returns
  `{:ok, %Rian.Manifest{}}` or `{:error, message}` — a missing file, an unreadable
  file, a malformed line, or a failed validation all surface as a clear message.
  """
  @rian_sig "pub def read(path String) (Manifest | String)"
  @spec read(Path.t()) :: {:ok, t()} | {:error, String.t()}
  def read(path \\ "rian.toml") do
    case File.read(path) do
      {:ok, text} -> parse(text)
      {:error, reason} -> {:error, "cannot read #{path}: #{:file.format_error(reason)}"}
    end
  end

  @doc "Parse manifest TOML text. Returns `{:ok, %Rian.Manifest{}}` or `{:error, message}`."
  @rian_sig "pub def parse(text String) (Manifest | String)"
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(text) when is_binary(text) do
    with {:ok, tables} <- tables(text) do
      build(tables)
    end
  end

  @doc """
  The nearest `rian.toml` at or above `start_dir` (default the CWD), as an absolute
  path, or `nil` if none exists up to the filesystem root. This is how a tool finds
  the **project root** from anywhere inside the tree (the `cargo`/`git` walk-up) — the
  anchor for the build-default target set (`Rian.Reach`) and `@external` file-reference
  resolution (ADR-0080 §2/§7).
  """
  @spec locate(Path.t()) :: Path.t() | nil
  def locate(start_dir \\ ".") do
    start_dir |> Path.expand() |> walk_up()
  end

  defp walk_up(dir) do
    candidate = Path.join(dir, "rian.toml")
    parent = Path.dirname(dir)

    cond do
      File.regular?(candidate) -> candidate
      parent == dir -> nil
      true -> walk_up(parent)
    end
  end

  @doc """
  The **project root** for `start_dir` — the directory of the nearest `rian.toml`
  (`locate/1`), or `start_dir` itself when there is no manifest above it. A relative
  `@external` file-reference resolves against this base, so it is stable regardless of
  which entry file inside the project is built/run (ADR-0080 §7).
  """
  @spec root(Path.t()) :: Path.t()
  def root(start_dir) do
    case locate(start_dir) do
      nil -> start_dir
      path -> Path.dirname(path)
    end
  end

  @doc """
  Run `fun` with the project's manifest configured: point `:rian_manifest` at the
  `rian.toml` located at or above `start_dir`, so `Rian.Reach.build_default` gates the
  compile against the project's declared `targets` (ADR-0080 §2). The previous value is
  restored afterwards, so this is the **entry-point boundary** (an escript subcommand, a
  mix task) opting a single build into its project context — not a global mutation that
  could leak into an unrelated compile. A no-op (beyond running `fun`) when no manifest
  is found. Returns `fun`'s result.
  """
  @spec with_project(Path.t(), (-> result)) :: result when result: var
  def with_project(start_dir \\ ".", fun) when is_function(fun, 0) do
    prev = Application.fetch_env(:rian_lab, :rian_manifest)

    case locate(start_dir) do
      nil -> :ok
      path -> Application.put_env(:rian_lab, :rian_manifest, path)
    end

    try do
      fun.()
    after
      case prev do
        {:ok, v} -> Application.put_env(:rian_lab, :rian_manifest, v)
        :error -> Application.delete_env(:rian_lab, :rian_manifest)
      end
    end
  end

  # ── the constrained-TOML reader: text -> %{"table" => %{"key" => value}} ──────

  defp tables(text) do
    text
    |> String.split(["\r\n", "\n"])
    |> Enum.map(&strip_comment/1)
    |> Enum.with_index(1)
    |> Enum.reduce({:ok, nil, %{}}, &fold_line/2)
    |> case do
      {:error, msg} -> {:error, msg}
      {:ok, _section, acc} -> {:ok, acc}
    end
  end

  defp fold_line({_line, _n}, {:error, _} = err), do: err

  defp fold_line({raw, n}, {:ok, section, acc}) do
    line = String.trim(raw)

    cond do
      line == "" ->
        {:ok, section, acc}

      table = table_header(line) ->
        {:ok, table, Map.put_new(acc, table, %{})}

      section == nil ->
        {:error, "rian.toml line #{n}: key outside any [table]: #{line}"}

      true ->
        case parse_kv(line) do
          {:ok, k, v} -> {:ok, section, put_in(acc, [section, k], v)}
          :error -> {:error, "rian.toml line #{n}: malformed entry: #{line}"}
        end
    end
  end

  # strip a trailing `# comment`, but never a `#` inside a `"…"` string.
  defp strip_comment(line), do: strip_comment(line, <<>>, false)
  defp strip_comment(<<>>, acc, _in?), do: acc

  defp strip_comment(<<?", rest::binary>>, acc, in?),
    do: strip_comment(rest, acc <> ~s("), not in?)

  defp strip_comment(<<?#, _::binary>>, acc, false), do: acc
  defp strip_comment(<<c, rest::binary>>, acc, in?), do: strip_comment(rest, acc <> <<c>>, in?)

  defp table_header(line) do
    case Regex.run(~r/^\[([a-z_]+)\]$/, line) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp parse_kv(line) do
    case String.split(line, "=", parts: 2) do
      [k, v] ->
        case parse_value(String.trim(v)) do
          {:ok, val} -> {:ok, String.trim(k), val}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  # the constrained subset has no escape sequences, so a string value contains neither
  # `"` nor `\`; `[^"\\]*` (not greedy `.*`) rejects a malformed `"a"b"` instead of
  # capturing `a"b`, and rejects a stray backslash (which has no meaning here and would
  # only break a generated `Cargo.toml`/`.app.src`/`build.gradle.kts` downstream).
  defp parse_value(<<?", _::binary>> = s) do
    case Regex.run(~r/^"([^"\\]*)"$/, s) do
      [_, inner] -> {:ok, inner}
      _ -> :error
    end
  end

  defp parse_value(<<?[, _::binary>> = s) do
    case Regex.run(~r/^\[(.*)\]$/, s) do
      [_, inner] -> parse_string_array(inner)
      _ -> :error
    end
  end

  defp parse_value(_other), do: :error

  # Split a `["a", "b"]` body into its quoted elements. Scanning quoted tokens (rather
  # than `String.split(",")`) keeps a comma *inside* a value intact (`"Last, First"`),
  # and the residue check — everything outside the quoted tokens must be commas/space —
  # still rejects malformed input (`["a" junk "b"]`) instead of silently dropping it.
  defp parse_string_array(inner) do
    trimmed = String.trim(inner)

    if trimmed == "" do
      {:ok, []}
    else
      items = Regex.scan(~r/"([^"\\]*)"/, trimmed) |> Enum.map(fn [_, v] -> v end)

      residue =
        Regex.replace(~r/"[^"\\]*"/, trimmed, "") |> String.replace(",", "") |> String.trim()

      if items != [] and residue == "", do: {:ok, items}, else: :error
    end
  end

  # ── tables -> validated struct ───────────────────────────────────────────────

  defp build(tables) do
    project = Map.get(tables, "project", %{})
    kind = Map.get(project, "kind", "lib")
    targets = Map.get(project, "targets", [])

    with {:ok, name} <- require_field(project, "name"),
         :ok <- validate_name(name),
         {:ok, version} <- require_field(project, "version"),
         :ok <- validate_kind(kind),
         {:ok, target_atoms} <- validate_targets(targets) do
      {:ok,
       %__MODULE__{
         name: name,
         version: version,
         kind: kind,
         license: Map.get(project, "license"),
         authors: Map.get(project, "authors", []),
         targets: target_atoms,
         deps: Map.get(tables, "deps", %{}),
         lint: Map.get(tables, "lint", %{})
       }}
    end
  end

  defp require_field(project, key) do
    case Map.get(project, key) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, "rian.toml: `[project]` is missing a non-empty `#{key}`"}
    end
  end

  # the project name becomes a crate name, an npm package, a Gradle `rootProject.name`,
  # and an Erlang application atom (`{application, <name>, …}`) — so it must be a safe
  # lowercase identifier (ADR-0080 §2 "snake_case"). Enforcing it here, at the single
  # source, is what lets every backend interpolate `name` without escaping.
  defp validate_name(name) do
    if Regex.match?(~r/^[a-z][a-z0-9_-]*$/, name),
      do: :ok,
      else:
        {:error,
         "rian.toml: `name` must be a lowercase identifier matching " <>
           "`[a-z][a-z0-9_-]*` (snake/kebab-case), got #{inspect(name)}"}
  end

  defp validate_kind(kind) when kind in @kinds, do: :ok

  defp validate_kind(kind),
    do: {:error, "rian.toml: `kind` must be one of #{inspect(@kinds)}, got #{inspect(kind)}"}

  defp validate_targets(targets) when is_list(targets) do
    known = Enum.map(Reach.targets(), &Atom.to_string/1)

    case targets -- known do
      [] -> {:ok, Enum.map(targets, &String.to_atom/1)}
      bad -> {:error, "rian.toml: unknown target(s) #{inspect(bad)}; known: #{inspect(known)}"}
    end
  end

  defp validate_targets(_), do: {:error, "rian.toml: `targets` must be an array of strings"}
end
