Code.require_file("../../support/loader.exs", __DIR__)
unless Code.ensure_loaded?(Jido.Test.Examples.AIModel), do: Code.require_file("../../support/ai_model.exs", __DIR__)

Jido.Test.Examples.Loader.require_source!("15_ai_basics/15_06_request_contract/agent.ex")

defmodule Jido.Examples.AI.RequestContractTest do
  use Jido.Test.Case, async: false
  import Mimic

  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("15_ai_basics/15_06_request_contract/agent.ex")
    :ok
  end

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.Examples.AI.RequestContract
  alias Jido.Test.Examples.AIModel

  test "preflight reports the selected visible tool and complete limits" do
    assert {:ok, %{params: params, tools: tools}} =
             RequestContract.Agent.preflight(%{
               input: "Look up status",
               tool_policy: %{visible: ["request_contract_lookup"]}
             })

    assert Enum.map(tools, & &1.name()) == [
             "request_contract_lookup",
             "request_contract_calculate"
           ]

    assert params.tool_policy.visible == ["request_contract_lookup"]
    assert params.limits.model_calls == 3
    assert params.limits.tool_calls == 2
  end

  test "the declared tools have typed local results" do
    assert {:ok, %{name: "project", value: "known"}} =
             Jido.Exec.run(RequestContract.Lookup, %{name: "project"}, %{})

    assert {:ok, %{sum: 5}} =
             Jido.Exec.run(RequestContract.Calculate, %{left: 2, right: 3}, %{})
  end

  test "one offline request returns IDs, usage, and ordered Session entries" do
    AIModel.expect_text("Ready.")
    agent = RequestContract.Agent.instantiate!(id: unique_id("request-contract"))

    assert {:ok, next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             RequestContract.Agent.cmd(
               agent,
               RequestContract.Agent.request_signal!(%{input: "Reply with Ready."})
             )

    assert reply.data.status == :completed
    assert reply.data.output == "Ready."
    assert is_binary(reply.data.request_id)
    assert is_binary(reply.data.run_id)
    assert reply.data.usage.total_tokens == 7

    assert Enum.map(next.state.session.thread.entries, & &1.seq) ==
             Enum.to_list(0..(next.state.session.thread.rev - 1))
  end
end
