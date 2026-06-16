defmodule Rian.PortSpec do
  @moduledoc """
  The **porting decision file** (`port.spec`) — the feedback loop for ADR-0075's
  port-analysis. A port of a compiler-shaped codebase leaves hundreds of `Unk####`
  placeholders and a handful of proposed `Sum#` dispatch clusters; but those aren't
  hundreds of distinct types — they're a few dozen real ones, each carrying ONE shared
  name across the whole program. So the human records a few **decisions** once and the
  tooling **re-resolves program-wide**:

      # port.spec — `Placeholder = RianType`
      Sum1 = Expr        # name a proposed dispatch cluster
      Sum2 = Pat
      Unk0042 = String   # pin a residual unknown

  Because each `Sum#`/`Unk####` is shared (one identity per logical type, linked through
  the call graph), substituting `Sum1 → Expr` once applies at *every* site — naming ~5–10
  sums collapses hundreds of placeholders. `mix rian.port_analysis --spec port.spec`
  applies the file and reports decisions-made vs placeholders-remaining.
  """

  @placeholder ~r/\b(?:Sum\d+|Unk\d+)\b/

  @doc "Parse a `port.spec` into a substitution map `%{placeholder => rian_type}`."
  @spec parse(String.t()) :: %{String.t() => String.t()}
  def parse(text) when is_binary(text) do
    text
    |> String.split("\n")
    # strip inline AND whole-line `#` comments (`Sum1 = Expr  # the E* nodes` → `Sum1 = Expr`)
    |> Enum.map(fn line -> line |> String.split("#", parts: 2) |> hd() |> String.trim() end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(fn line ->
      case String.split(line, "=", parts: 2) do
        [lhs, rhs] ->
          {l, r} = {String.trim(lhs), String.trim(rhs)}
          if l != "" and r != "", do: [{l, r}], else: []

        _ ->
          []
      end
    end)
    |> Map.new()
  end

  @doc "Load a `port.spec` from a path (empty map if it doesn't exist)."
  @spec load(String.t() | nil) :: %{String.t() => String.t()}
  def load(nil), do: %{}
  def load(path), do: if(File.exists?(path), do: parse(File.read!(path)), else: %{})

  @doc """
  Substitute every `Sum#`/`Unk####` placeholder in a rendered type string with its
  `port.spec` decision (program-wide re-resolution). Unmapped placeholders stay.
  """
  @spec apply_subs(String.t() | nil, %{String.t() => String.t()}) :: String.t() | nil
  def apply_subs(str, subs) when is_binary(str) and map_size(subs) > 0,
    do: Regex.replace(@placeholder, str, fn whole -> Map.get(subs, whole, whole) end)

  def apply_subs(str, _subs), do: str

  @doc "Every distinct placeholder token in a rendered type string."
  @spec placeholders(String.t() | nil) :: [String.t()]
  def placeholders(str) when is_binary(str),
    do: @placeholder |> Regex.scan(str) |> Enum.map(&hd/1) |> Enum.uniq()

  def placeholders(_), do: []

  @doc """
  Generate a stub `port.spec` from analysis `data` — every proposed sum (with its
  co-occurring members as a hint) and every residual unknown (with its site count),
  each with a blank assignment for the human to fill. Already-decided entries (in
  `subs`) keep their value, so regenerating is idempotent against an edited spec.
  """
  @spec template(map(), %{String.t() => String.t()}) :: String.t()
  def template(data, subs \\ %{}) do
    sum_lines =
      data.sums
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {members, i} ->
        [
          "# co-occur in dispatch: #{Enum.join(members, " | ")}",
          "Sum#{i} = #{subs["Sum#{i}"] || ""}"
        ]
      end)

    unk_lines =
      data.wp.unks
      |> Enum.sort()
      |> Enum.flat_map(fn {name, sites} ->
        ["# #{length(sites)} site(s)", "#{name} = #{subs[name] || ""}"]
      end)

    Enum.join(
      [
        "# port.spec — porting decisions (ADR-0075). `Placeholder = RianType`.",
        "# Name a proposed dispatch sum or pin a residual unknown; applied program-wide",
        "# (each placeholder is shared, so one decision re-resolves every site).",
        "# Re-run: mix rian.port_analysis <dir> -o OUT.md --spec port.spec",
        "",
        "# ── proposed sums (name the dispatch clusters) ──",
        Enum.join(sum_lines, "\n"),
        "",
        "# ── residual unknowns (pin where you can; leave blank to defer) ──",
        Enum.join(unk_lines, "\n")
      ],
      "\n"
    ) <> "\n"
  end
end
