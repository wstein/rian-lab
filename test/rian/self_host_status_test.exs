defmodule Rian.SelfHostStatusTest do
  @moduledoc """
  Gate for the self-hosting status snapshot (ADR-0063 §4): the marching boundary is a
  measured number, and `docs/self-host-status.md` must stay in sync with the computed
  `Rian.SelfHost` data — drift fails the build, so "% self-hosted" can't rot.
  """
  use ExUnit.Case, async: true

  alias Rian.SelfHost

  @snapshot Path.join([File.cwd!(), "docs", "self-host-status.md"])

  test "docs/self-host-status.md is the current snapshot (regenerate if this fails)" do
    assert File.exists?(@snapshot),
           "missing docs/self-host-status.md — write `Rian.SelfHost.status_markdown/0` to it"

    assert File.read!(@snapshot) == SelfHost.status_markdown(),
           "docs/self-host-status.md is stale. Regenerate:\n" <>
             "    File.write!(\"docs/self-host-status.md\", Rian.SelfHost.status_markdown())"
  end

  test "every cited self-host evidence source exists (no dangling status claim)" do
    missing = Enum.reject(SelfHost.evidence_files(), &File.exists?/1)
    assert missing == [], "status cites missing self-host sources: #{inspect(missing)}"
  end

  test "the percent is a sane, computed measure that matches the stage weights" do
    pct = SelfHost.percent()
    assert pct in 0..100

    # the headline number must appear in the rendered doc (not a hardcoded string)
    assert SelfHost.status_markdown() =~ "#{pct}% self-hosted"

    # honesty floor: not every stage is fully self-hosted, so we are not at 100%.
    # (Every stage is now at least :partial, so :not_started may legitimately be 0;
    # the floor that still bites is that most stages are partial, not self_hosted.)
    refute pct == 100, "self-hosting is not complete; a 100% headline would be dishonest"

    assert SelfHost.count(:self_hosted) < length(SelfHost.stages()),
           "not every stage is fully self-hosted; 100% would be dishonest"
  end

  test "the report renders every status badge — incl. `:not_started` and a source-less stage" do
    # No real stage currently sits at `:not_started`, but the reporter must still
    # render that vocabulary (a future stage could regress/be added). Drive the row
    # renderer with a synthetic source-less, not-started stage via `status_markdown/1`.
    synthetic = [
      %{name: "Synthetic", role: "test seam", status: :not_started, source: nil, test: nil, note: "n/a"}
    ]

    row = SelfHost.status_markdown(synthetic)
    # not-started badge is `—`, and a source-less stage's evidence is also `—`
    assert row =~ "| Synthetic | test seam | — | — | n/a |"

    # and the real badges render too (sanity over the live pipeline)
    live = SelfHost.status_markdown()
    assert live =~ "🟡 partial" or live =~ "✅ yes"
  end

  test "only stages with an equivalence/fixpoint test are marked self_hosted (teeth)" do
    # a `:self_hosted` claim must cite both a Rian source AND a test — a port with no
    # equivalence lock is at most `:partial`. Guards against inflating the number.
    for s <- SelfHost.stages(), s.status == :self_hosted do
      assert s.source, "#{s.name} claims :self_hosted with no Rian source"
      assert s.test, "#{s.name} claims :self_hosted with no equivalence/fixpoint test"
    end
  end
end
