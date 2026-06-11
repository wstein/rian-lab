defmodule Rian.Q do
  @moduledoc """
  Runtime support for the `?` error/Option propagation operator on the BEAM.

  Rian lowers `e?` to `Rian.Q.unwrap(e)` and wraps the enclosing function or
  closure body in `try ... catch {:#{:__rian_q__}, v} -> v end`. `unwrap/1`
  returns the success payload of a `Result`/`Option`, or throws the whole value
  so the wrapper short-circuits and returns it — the BEAM-side equivalent of
  Rust's native `?`. The tag atom here MUST match `Rian.Lower`'s `@propagate_tag`.

  Keeping the unwrap in a function (rather than an inlined `case`) means its
  argument is `term()`, so both the `Result` and `Option` clauses stay live and
  the generated code compiles without "clause will never match" warnings.
  """

  @doc "Unwrap `{:ok, v}` / `{:some, v}`, or throw the value to propagate it."
  @spec unwrap(term()) :: term()
  def unwrap({:ok, v}), do: v
  def unwrap({:some, v}), do: v
  def unwrap(other), do: throw({:__rian_q__, other})
end
