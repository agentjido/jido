Code.require_file("../../support/loader.exs", __DIR__)
unless Code.ensure_loaded?(JidoTest.Examples.AIModel), do: Code.require_file("../../support/ai_model.exs", __DIR__)

JidoTest.Examples.Loader.require_source!("15_ai_basics/15_04_controls/agent.ex")

defmodule JidoTest.Examples.AI.ControlsTest do
  use JidoTest.Case, async: false
  import Mimic

  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("15_ai_basics/15_04_controls/agent.ex")
    :ok
  end

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.Examples.AI.Controls
  alias JidoTest.Examples.AIModel

  test "the local membership Action denies missing authorization" do
    assert {:ok, %{allowed: true}} = Jido.Exec.run(Controls.MemberOnly, %{input: "hello"}, %{role: :member})

    assert {:error, %{details: %{reason: :access_denied}}} =
             Jido.Exec.run(Controls.MemberOnly, %{input: "hello"}, %{})
  end

  test "the Agent exposes bounded reasoning limits" do
    assert %{defaults: %{limits: limits}} = Controls.Agent.explain()
    assert limits.model_calls == 1
    assert limits.tool_rounds == 0
    assert limits.elapsed_ms == 5_000
  end

  test "a disabled tool policy completes without tool work" do
    AIModel.expect_text("Approved [source]")
    agent = Controls.Agent.instantiate!(id: unique_id("controls-ai"))

    request =
      Controls.Agent.request_signal!(%{
        input: "Answer this",
        tool_policy: %{requirement: :disabled}
      })

    assert {:ok, _next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             Controls.Agent.cmd(agent, request)

    assert reply.data.output == "Approved [source]"
    assert reply.data.tool_calls == 0
  end
end
