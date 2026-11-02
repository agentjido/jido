defmodule Jido.AI.Contract.NoReasoningAgent do
  def definition, do: %{routes: [], plugins: []}
end

defmodule Jido.AI.Contract.BareReasoningAgent do
  def definition do
    %{
      routes: [
        %{
          path: "jido.ai.request",
          handler: %{kind: :flow, target: Jido.AI.Reasoning.ReAct},
          defaults: %{}
        }
      ],
      plugins: [%{provider: String, data: %{}}]
    }
  end
end

defmodule Jido.AI.Contract.StrategiesTest do
  use Covenant.Case, component: "jido_ai.strategies", async: true

  alias Jido.AI.Reasoning
  alias Jido.AI.Reasoning.Adaptive.Actions.Select

  alias Jido.AI.Reasoning.{
    Adaptive,
    AlgorithmOfThoughts,
    ChainOfDraft,
    ChainOfThought,
    GraphOfThoughts,
    TreeOfThoughts,
    TRM
  }

  @strategies [
    Adaptive,
    ChainOfThought,
    ChainOfDraft,
    AlgorithmOfThoughts,
    GraphOfThoughts,
    TreeOfThoughts,
    TRM
  ]

  @tag obligation: ["jido_ai.strategies.I1", "jido_ai.strategies.I2"]
  test "standard strategies accept the common request and expose explicit Flows" do
    params = %{
      input: "Inspect this request.",
      instructions: "Return one answer.",
      model: "openai:gpt-4o-mini",
      options: %{temperature: 0.0},
      prompt_cache: %{enabled: false},
      context: %{max_messages: 16, max_bytes: 16_384},
      limits: %{
        elapsed_ms: 30_000,
        input_tokens: 1_000,
        output_tokens: 500,
        total_tokens: 1_500,
        total_cost: 1.0
      }
    }

    for strategy <- @strategies do
      assert {:ok, validated} = strategy.validate_params(params)
      assert validated.input == params.input
      assert validated.model == params.model
      assert %Jido.Flow{} = strategy.flow()
    end
  end

  @tag obligation: ["jido_ai.strategies.I3", "jido_ai.strategies.I4"]
  test "strategy-specific rounds keep model attempts and completion visible" do
    linear_rounds = [
      ChainOfThought.ModelRound,
      ChainOfDraft.ModelRound,
      AlgorithmOfThoughts.ModelRound
    ]

    for model_round <- linear_rounds do
      assert %Jido.Flow{
               components: %{
                 "model" => %{call: %{target: Jido.AI.Reasoning.Actions.CallModel}},
                 "record_attempt" => %{
                   call: %{target: Jido.AI.Reasoning.Actions.RecordModelAttempt}
                 },
                 "complete" => %{kind: :call}
               }
             } = model_round.flow()
    end

    for model_round <- [GraphOfThoughts.ModelRound, TreeOfThoughts.ModelRound, TRM.ModelRound] do
      assert %Jido.Flow{components: components} = model_round.flow()
      assert components["model"].call.target == Jido.AI.Reasoning.Actions.CallModel

      assert components["record_attempt"].call.target ==
               Jido.AI.Reasoning.Actions.RecordModelAttempt

      routing = components["next"] || components["advance"]
      assert routing.kind == :invoke
    end

    assert %Jido.Flow{components: %{"reason" => %{kind: :invoke}}} = Adaptive.flow()
  end

  @tag obligation: "jido_ai.strategies.I1"
  test "reasoning preflight rejects invalid request and Agent boundaries" do
    assert {:error, :invalid_input} =
             Reasoning.preflight(Jido.AITest.SimpleAgent, [:not_a_keyword])

    assert {:error, :invalid_input} = Reasoning.preflight(Jido.AITest.SimpleAgent, :invalid)

    assert {:error, %ArgumentError{message: message}} =
             Reasoning.preflight(Jido.AI.Contract.NoReasoningAgent, %{})

    assert message =~ "does not define one jido.ai.request reasoning Flow"
  end

  @tag obligation: "jido_ai.strategies.I1"
  test "reasoning inspection and adaptive defaults remain explicit" do
    assert %{tools: [], reasoning: Jido.AI.Reasoning.ReAct} =
             Reasoning.explain(Jido.AI.Contract.BareReasoningAgent)

    assert {:ok, %{strategy: :trm}} = Select.run(%{input: "solve this puzzle"}, %{})

    long_input =
      "one two three four five six seven eight nine ten eleven twelve thirteen"

    assert {:ok, %{strategy: :chain_of_thought}} = Select.run(%{input: long_input}, %{})

    assert {:ok, %{strategy: :chain_of_draft}} =
             Select.run(%{input: [%{text: "short"}]}, %{})
  end
end
