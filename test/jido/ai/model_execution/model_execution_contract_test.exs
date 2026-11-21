defmodule Jido.AI.ModelExecution.ContractTest do
  use Covenant.Case, component: "jido_ai.model_execution", async: true

  alias Jido.AI.{Budget, Context, Usage}
  alias Jido.AI.Actions.Embed
  alias Jido.AI.Context.Snapshot
  alias Jido.AI.Reasoning.Actions.CallModel

  @tag obligation: ["jido_ai.model_execution.I1", "jido_ai.model_execution.I2"]
  test "model admission returns one stable outcome when a request budget is spent" do
    for stream <- [false, true] do
      turn = %{
        stream: stream,
        models: ["first:model", "fallback:model"],
        model_index: 0,
        model_calls: 1,
        max_model_calls: 1,
        started_at_ms: 1,
        max_elapsed_ms: 10_000,
        usage: Usage.zero()
      }

      assert {:error, :model_calls, "maximum model calls reached"} =
               Budget.before_model(turn, 2)

      assert {:ok, %{outcome: outcome}} =
               CallModel.run(%{turn: turn, context: nil}, %{})

      assert outcome.status == :budget
      assert outcome.retryable == false
      assert outcome.model == "first:model"
    end
  end

  @tag obligation: "jido_ai.model_execution.I3"
  test "usage keeps cache counters and provider-reported cost" do
    usage =
      Usage.add(Usage.zero(), %{
        input_tokens: 12,
        output_tokens: 3,
        cache_read_tokens: 7,
        cache_write_tokens: 2,
        total_cost: 0.25
      })

    assert usage.input_tokens == 12
    assert usage.output_tokens == 3
    assert usage.cache_read_tokens == 7
    assert usage.cache_write_tokens == 2
    assert usage.total_cost == 0.25
  end

  @tag obligation: "jido_ai.model_execution.I3"
  test "usage adds tool-use tokens and reasoning cost to an older aggregate" do
    older = Map.drop(Usage.zero(), [:tool_use_input_tokens, :reasoning_cost])
    attempt = %{input_tokens: 10, output_tokens: 5, tool_use_input_tokens: 2, reasoning_cost: 0.04, total_cost: 0.10}
    usage = older |> Usage.add(attempt) |> Usage.add(attempt) |> Usage.add(%{})

    assert usage.tool_use_input_tokens == 4
    assert usage.reasoning_cost == 0.08
    assert usage.total_tokens == 34
    assert usage.total_cost == 0.20
  end

  @tag obligation: ["jido_ai.model_execution.I4", "jido_ai.model_execution.I5"]
  test "prepared contexts have a safe portable snapshot for either call mode" do
    request = ReqLLM.Context.new([ReqLLM.Context.user("Secret input")])
    assert {:ok, context} = Context.new(request)

    assert {:ok, context} =
             Context.prepare(context,
               model: "openai:gpt-4o-mini",
               options: [stream: true, api_key: "not-portable"]
             )

    encoded = context |> Snapshot.new(content: :none) |> Snapshot.encode()
    decoded = Snapshot.decode!(encoded)

    assert decoded["stage"] == "prepared"
    assert get_in(decoded, ["request", "model"]) == "openai:gpt-4o-mini"
    refute encoded =~ "Secret input"
    refute encoded =~ "not-portable"
  end

  @tag obligation: "jido_ai.model_execution.I6"
  test "embedding action accepts one input or an ordered input batch" do
    assert {:ok, %{input: "one"}} = Embed.validate_params(%{input: "one"})
    assert {:ok, %{options: %{dimensions: 16}}} = Embed.validate_params(%{input: "one", options: %{"dimensions" => 16}})
    assert {:error, _reason} = Embed.validate_params(%{input: "one", options: %{"unrecognized_model_option" => true}})
    assert {:ok, %{input: ["one", "two"]}} = Embed.validate_params(%{input: ["one", "two"]})
    assert {:error, _reason} = Embed.validate_params(%{input: ["one", 2]})
  end
end
