defmodule Jido.AI.Contract.ReActTest do
  use Covenant.Case, component: "jido_ai.react", async: true

  alias Jido.AI.Reasoning.ReAct

  alias Jido.AI.Reasoning.Actions, as: SharedActions

  alias Jido.AI.Reasoning.ReAct.Actions.{
    DecideNext,
    DetectToolCycle,
    ExpandNext,
    RecordToolResults
  }

  alias Jido.AITest.Tools

  @tag obligation: ["jido_ai.react.I1", "jido_ai.react.I2"]
  test "validated tool calls expand in model order" do
    input = %{
      turn: %{
        tools: [Tools.Add, Tools.Multiply],
        model_outcome: %{
          tool_calls: [
            %{id: "multiply-1", name: "multiply", arguments: %{"left" => 2, "right" => 3}},
            %{id: "add-1", name: "add", arguments: %{"left" => 4, "right" => 5}}
          ]
        }
      }
    }

    assert {:continue, ^input, %Jido.Flow{} = flow} =
             ExpandNext.run(%{kind: :tools, input: input}, %{})

    assert [first, second] = flow.components["tools"].actions
    assert first.name == "tool_0"
    assert first.call.params.call.name == "multiply"
    assert second.name == "tool_1"
    assert second.call.params.call.name == "add"

    assert {:error, {:unknown_tool, "missing"}} =
             ExpandNext.run(
               %{
                 kind: :tools,
                 input: %{
                   turn: %{
                     tools: [Tools.Add],
                     model_outcome: %{
                       tool_calls: [%{id: "bad-1", name: "missing", arguments: %{}}]
                     }
                   }
                 }
               },
               %{}
             )
  end

  @tag obligation: ["jido_ai.react.I3", "jido_ai.react.I4"]
  test "review persistence stays an explicit graph step" do
    assert %Jido.Flow{
             components: %{
               "request" => %{
                 kind: :call,
                 call: %{target: Jido.AI.Reasoning.ReAct.Actions.RequestToolReview}
               },
               "decision" => %{kind: :wait},
               "next" => %{
                 kind: :invoke,
                 decision: %{target: Jido.AI.Reasoning.ReAct.Actions.ResolveToolReview},
                 expander: %{target: ExpandNext}
               }
             }
           } = ReAct.ToolReview.flow()

    assert %Jido.Flow{
             components: %{
               "loop" => %{kind: :invoke, expander: %{target: ExpandNext}}
             }
           } = ReAct.flow()
  end

  @tag obligation: ["jido_ai.react.I1", "jido_ai.react.I2", "jido_ai.react.I3"]
  test "the standard ReAct graphs expose every ordered component" do
    assert %Jido.Flow{components: root_components} = ReAct.flow()
    assert map_size(root_components) == 4

    assert %{
             "start_request" => %{kind: :call, call: %{target: SharedActions.StartRequest}},
             "input_guard" => %{kind: :call, call: %{target: SharedActions.GuardInput}},
             "loop" => %{
               kind: :invoke,
               decision: %{target: SharedActions.DecideInput},
               expander: %{target: ExpandNext}
             },
             "finalize" => %{kind: :call, call: %{target: SharedActions.FinalizeTurn}}
           } = root_components

    assert %Jido.Flow{components: model_components} = ReAct.ModelRound.flow()
    assert map_size(model_components) == 6

    assert %{
             "project" => %{kind: :call, call: %{target: SharedActions.ProjectConversation}},
             "model" => %{kind: :call, call: %{target: SharedActions.CallModel}},
             "output_guard" => %{kind: :call, call: %{target: SharedActions.GuardOutput}},
             "record_attempt" => %{
               kind: :call,
               call: %{target: SharedActions.RecordModelAttempt}
             },
             "detect_cycle" => %{kind: :call, call: %{target: DetectToolCycle}},
             "next" => %{
               kind: :invoke,
               decision: %{target: DecideNext},
               expander: %{target: ExpandNext}
             }
           } = model_components

    assert map_size(ReAct.ToolReview.flow().components) == 3
  end

  @tag obligation: "jido_ai.react.I6"
  test "each completed tool call creates one durable attempt observation" do
    turn = %{
      session: Jido.Session.new(id: "react-contract", now: 1) |> Jido.Session.encode(),
      request_id: "request-1",
      run_id: "run-1",
      max_tool_output_bytes: 4_096,
      model_attempt: 1,
      tool_rounds: 0,
      tool_call_count: 0,
      tool_error_count: 0,
      tool_attempts: [],
      review_tools: ["add"],
      model_outcome: %{kind: :tool_calls}
    }

    execution = %{
      version: 1,
      call: %{id: "add-1", name: "add", arguments: %{left: 2, right: 3}},
      tool: %{kind: :action, name: "add", module: "Elixir.Jido.AITest.Tools.Add"},
      outcome: %{status: :ok, value: %{sum: 5}},
      started_at_ms: 2,
      completed_at_ms: 3,
      duration_ms: 1,
      effects_count: 0
    }

    results = [
      %{
        id: "add-1",
        name: "add",
        outcome: %{status: :ok, value: execution}
      }
    ]

    assert {:ok, %{turn: next_turn}} =
             RecordToolResults.run(%{turn: turn, results: results}, %{})

    assert next_turn.tool_rounds == 1
    assert next_turn.tool_call_count == 1
    assert next_turn.tool_error_count == 0
    assert [attempt] = next_turn.tool_attempts
    assert attempt.tool_call_id == "add-1"
    assert attempt.input == %{left: 2, right: 3}
    assert attempt.status == :ok
    assert attempt.output == %{"sum" => 5}
    assert attempt.tool_round == 1
    assert attempt.review == %{required: true, status: :approved}

    session = Jido.Session.decode!(next_turn.session)
    assert [entry] = Jido.Thread.filter_by_kind(session.thread, :ai_tool_attempt)
    assert entry.payload["version"] == 1
    assert entry.payload["tool_call_id"] == "add-1"
    assert entry.refs.request_id == "request-1"
    assert entry.refs.run_id == "run-1"
  end

  @tag obligation: "jido_ai.react.I5"
  test "cycle signatures ignore provider call IDs" do
    first = [%{id: "provider-1", name: "add", arguments: %{"left" => 2, "right" => 3}}]
    second = [%{id: "provider-2", name: "add", arguments: %{"left" => 2, "right" => 3}}]
    changed = [%{id: "provider-3", name: "add", arguments: %{"left" => 3, "right" => 3}}]

    assert DetectToolCycle.signature(first) == DetectToolCycle.signature(second)
    refute DetectToolCycle.signature(first) == DetectToolCycle.signature(changed)
  end

  @tag obligation: "jido_ai.react.I7"
  test "tool limits stop a new batch before expansion" do
    turn = %{
      model_outcome: %{kind: :tool_calls, tool_calls: [%{name: "add"}]},
      tool_rounds: 2,
      max_tool_rounds: 2,
      tool_call_count: 0,
      max_tool_calls: 5
    }

    assert {:ok, %{kind: :complete, output: %{result: result}}} =
             DecideNext.run(%{turn: turn}, %{})

    assert result.status == :blocked
    assert result.reason_code == :limits
    assert result.reason == "maximum tool rounds reached"
  end
end
