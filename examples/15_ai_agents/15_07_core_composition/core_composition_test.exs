Code.require_file("agent.ex", __DIR__)

defmodule Jido.Examples.AI.CoreCompositionTest do
  use Jido.Test.Case, async: false
  import Mimic

  @moduletag :integration

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.Examples.AI.CoreComposition
  alias Jido.Test.Examples.AIModel

  test "the application Plugin and AI Plugin share one Agent definition" do
    assert Enum.map(CoreComposition.Agent.definition().plugins, & &1.provider) == [
             Jido.AI.Agent.Plugin,
             CoreComposition.Audit
           ]

    agent = CoreComposition.Agent.instantiate!(id: unique_id("composition-ai"))
    assert agent.state == %{session: nil}
  end

  test "the composed Agent runs the normal reasoning route" do
    AIModel.expect_text("A composed answer.")
    agent = CoreComposition.Agent.instantiate!(id: unique_id("composition-ai"))

    assert {:ok, next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             CoreComposition.Agent.cmd(
               agent,
               CoreComposition.Agent.request_signal!(%{input: "Answer this"})
             )

    assert reply.data.output == "A composed answer."
    assert next.state.session.thread.rev > 0
  end
end
