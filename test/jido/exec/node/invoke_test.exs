defmodule Jido.Exec.Node.InvokeTest do
  use Covenant.Case, component: "jido_action.boundary", async: true

  alias Jido.Action.Error.{
    ConfigurationError,
    ExecutionFailureError,
    InvalidInputError
  }

  alias Jido.Exec
  alias Jido.Exec.Frame
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Instruction
  alias Runic.Workflow

  defmodule Decide do
    use Jido.Action, name: "invoke_test_decide"

    @impl true
    def run(%{mode: "effects"} = params, _context), do: {:ok, params, [:decision]}
    def run(params, _context), do: {:ok, params}
  end

  defmodule Finalize do
    use Jido.Action, name: "invoke_test_finalize"

    @impl true
    def run(%{value: value, effects: true}, _context), do: {:ok, %{final: value}, [:target]}
    def run(%{value: value}, _context), do: {:ok, %{final: value}}
  end

  defmodule Expand do
    use Jido.Action, name: "invoke_test_expand"

    @impl true
    def run(%{mode: "continue", value: value}, _context),
      do: {:continue, %{value: value}, Finalize}

    def run(%{mode: "effects", value: value}, _context),
      do: {:continue, %{value: value, effects: true}, Finalize}

    def run(%{mode: "runtime_flow", value: value}, _context) do
      flow =
        Jido.Flow.new!(%{
          name: "invoke_runtime_flow",
          components: [
            %{
              kind: :step,
              name: "finalize",
              action: Finalize,
              params: %{value: Jido.Flow.Ref.input(:value)}
            }
          ],
          output: Jido.Flow.Ref.result("finalize")
        })

      {:continue, %{value: value}, flow}
    end

    def run(%{mode: "runtime_wait"}, _context) do
      flow =
        Jido.Flow.new!(%{
          name: "invoke_runtime_wait",
          components: [%{kind: :await, name: "event", event: "continue"}],
          output: Jido.Flow.Ref.result("event")
        })

      {:continue, %{}, flow}
    end

    def run(%{mode: "invalid_input", value: value}, _context),
      do: {:continue, %{value: value}, JidoActionTest.Fixtures.Actions.Add}

    def run(%{mode: "invalid_output", value: value}, _context),
      do: {:continue, %{value: value}, JidoActionTest.Fixtures.Actions.InvalidOutput}

    def run(%{mode: "target_error", value: value}, _context),
      do: {:continue, %{value: value}, JidoActionTest.Fixtures.Actions.ErrorWithExtrasAction}

    def run(%{mode: "finish", value: value}, _context), do: {:ok, %{final: value}, [:expander]}
    def run(%{mode: "bad_target", value: value}, _context), do: {:continue, %{value: value}, Enum}
    def run(%{mode: "refuse"}, _context), do: {:error, "expander refused", [:discarded]}
    def run(%{mode: "improper"}, _context), do: {:ok, %{done: true}, [:a | :b]}
  end

  defmodule DecisionWithEffects do
    use Jido.Action, name: "invoke_decision_effects"
    def run(params, _context), do: {:ok, params, [:decision]}
  end

  defmodule FinalOutput do
    use Jido.Action, name: "invoke_final_output"
    def run(%{value: value}, _context), do: {:ok, %{final: value}, [:expanded, :expanded]}
  end

  defmodule HandoffAttempt do
    use Jido.Action, name: "invoke_handoff_attempt"
    def run(params, _context), do: {:handoff, params, Finalize}
  end

  defmodule BoundTarget do
    use Jido.Action, name: "invoke_bound_target"

    @impl true
    def run(%{value: value, amount: amount, source: source}, context) do
      {:ok,
       %{
         value: value + amount,
         source: source,
         tenant: Map.get(context, :tenant),
         shared: Map.get(context, :shared)
       }}
    end
  end

  defmodule AlternateBoundTarget do
    use Jido.Action, name: "invoke_alternate_bound_target"

    @impl true
    def run(%{value: value, amount: amount, source: source}, _context) do
      {:ok, %{value: value * amount, source: source, target: :alternate}}
    end
  end

  defmodule BoundFlow do
    use Jido.Flow, name: "invoke_bound_flow"

    flow do
      step "target",
        action: BoundTarget,
        params: %{
          value: input(:value),
          amount: input(:amount),
          source: input(:source)
        }

      output result("target")
    end
  end

  defmodule ExpandBound do
    use Jido.Action, name: "invoke_expand_bound"

    @impl true
    def run(%{value: value, target: target}, _context) do
      {:continue, %{value: value, source: :continuation}, target}
    end
  end

  defmodule ExpandInvalidBound do
    use Jido.Action, name: "invoke_expand_invalid_bound"

    @impl true
    def run(%{target: target}, _context), do: {:continue, :invalid, target}
  end

  defmodule Combine do
    use Jido.Action, name: "invoke_combine"

    @impl true
    def run(%{left: left, right: right}, _context),
      do: {:ok, %{mode: "finish", value: left + right}}
  end

  @tag obligation: ["jido_action.boundary.I4", "jido_action.boundary.I8"]
  test "a direct Invoke result retains decision and expander effects" do
    flow =
      Flow.new!(%{
        name: "invoke_final_effects",
        components: [
          %{
            kind: :invoke,
            name: "next",
            decision: DecisionWithEffects,
            expander: FinalOutput,
            params: %{value: Ref.input(:value)}
          }
        ],
        output: Ref.result("next")
      })

    assert Exec.run(flow, %{value: 4}) == {:ok, %{final: 4}, [:decision, :expanded, :expanded]}
  end

  @tag obligation: "jido_action.boundary.I8"
  test "an expander continuation runs the selected target" do
    assert Exec.run(flow(), %{mode: "continue", value: 4}) == {:ok, %{final: 4}}
  end

  @tag obligation: "jido_action.boundary.I8"
  test "an expander continuation runs a runtime Flow target" do
    assert Exec.run(flow(), %{mode: "runtime_flow", value: 4}) == {:ok, %{final: 4}}
  end

  @tag obligation: ["jido_action.boundary.I4", "jido_action.boundary.I8"]
  test "an Action continuation uses a native Call and keeps ordered effects" do
    {completed, observation} =
      flow()
      |> Exec.compile!()
      |> Workflow.execute(Jido.Exec.Fact.local_value(Frame.new(%{mode: "effects", value: 4})))

    assert Exec.result(completed, observation) == {:ok, %{final: 4}, [:decision, :target]}
    nodes = Multigraph.vertices(completed.graph)
    assert Enum.count(nodes, &is_struct(&1, Runic.Workflow.Call)) == 1
    assert Enum.count(nodes, &is_struct(&1, Runic.Workflow.ChildInvocation.Occurrence)) == 1
    assert Enum.count(nodes, &is_struct(&1, Jido.Exec.Node.Invoke.Finish)) == 1
  end

  @tag obligation: "jido_action.boundary.I8"
  test "an Action continuation keeps local parent and target values" do
    value = {self(), make_ref(), fn -> :local end}
    assert Exec.run(flow(), %{mode: "continue", value: value}) == {:ok, %{final: value}}
  end

  @tag obligation: "jido_action.boundary.I8"
  test "different input occurrences use their own Action parameters" do
    definition = Exec.compile!(flow())
    first_input = Jido.Exec.Fact.local_value(Frame.new(%{mode: "continue", value: 1}))
    second_input = Jido.Exec.Fact.local_value(Frame.new(%{mode: "continue", value: 2}))
    {first, first_scope} = Workflow.execute(definition, first_input)
    {second, second_scope} = Workflow.execute(first, second_input)

    assert Exec.result(first, first_scope) == {:ok, %{final: 1}}
    assert Exec.result(second, second_scope) == {:ok, %{final: 2}}

    occurrences =
      Enum.filter(
        Multigraph.vertices(second.graph),
        &is_struct(&1, Runic.Workflow.ChildInvocation.Occurrence)
      )

    assert length(occurrences) == 2
    assert length(Enum.uniq_by(occurrences, & &1.hash)) == 2
  end

  @tag obligation: "jido_action.boundary.I8"
  test "completion and target predicates reject missing or unrelated values" do
    frame = Frame.new(%{})

    child_request =
      %Runic.Workflow.ChildInvocation{target: :target, input: frame, output: :out}

    assert Jido.Exec.Node.Invoke.finished?(child_request, "next") == false

    assert Jido.Exec.Node.Invoke.finished?(frame, nil) == false
    assert Jido.Exec.Node.Invoke.finished?(frame, "next") == false

    nil_result = Frame.put_result(frame, "next", nil, [])
    assert Jido.Exec.Node.Invoke.finished?(nil_result, "next") == false

    assert Jido.Exec.Node.Invoke.target?(frame, "target") == false

    assert Jido.Exec.Node.Invoke.target?(
             {:jido_invoke_flow_target, "other", frame},
             "target"
           ) == false

    condition = Jido.Exec.Node.Invoke.target_condition(:next, "next", "target")

    assert %Runic.Workflow.Condition{
             name: "__jido_invoke__/next/route/target",
             arity: 1
           } = condition

    assert condition.work.({:jido_invoke_flow_target, "target", frame}) == true
    assert condition.work.({:jido_invoke_flow_target, "other", frame}) == false
  end

  @tag obligation: ["jido_action.boundary.I5", "jido_action.boundary.I8"]
  test "dynamic target identity includes the Invoke and selected target" do
    frame = Frame.new(%{})
    first_node = invoke_node(:first)
    second_node = invoke_node(:second)

    first_target = Instruction.new!(target: BoundTarget, params: %{amount: 2})
    alternate_target = Instruction.new!(target: AlternateBoundTarget, params: %{amount: 2})

    {%Runic.Workflow.ChildInvocation{target: %{name: first_name}}, _apply} =
      Jido.Exec.Node.Invoke.expansion(first_node, first_target, %{}, frame, %{})

    {%Runic.Workflow.ChildInvocation{target: %{name: alternate_name}}, _apply} =
      Jido.Exec.Node.Invoke.expansion(first_node, alternate_target, %{}, frame, %{})

    {%Runic.Workflow.ChildInvocation{target: %{name: second_name}}, _apply} =
      Jido.Exec.Node.Invoke.expansion(second_node, first_target, %{}, frame, %{})

    {{:jido_invoke_flow_target, first_flow_id, ^frame}, _apply} =
      Jido.Exec.Node.Invoke.expansion(first_node, runtime_target_flow(11), %{}, frame, %{})

    {{:jido_invoke_flow_target, second_flow_id, ^frame}, _apply} =
      Jido.Exec.Node.Invoke.expansion(first_node, runtime_target_flow(22), %{}, frame, %{})

    first_target_id = first_name |> String.split("/") |> List.last()
    second_target_id = second_name |> String.split("/") |> List.last()

    call_data =
      {first_target.params, first_target.context}
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))

    expected_target_id =
      Runic.Identity.digest(:component_definition, %{
        kind: "jido_invoke_target",
        version: 1,
        invoke: inspect(first_node.id),
        target: %{
          module: BoundTarget,
          version: BoundTarget.module_info(:md5)
        },
        call_data: call_data
      })
      |> to_string()

    assert first_name != alternate_name
    assert first_name != second_name
    assert first_target_id == expected_target_id
    assert first_target_id != second_target_id
    assert first_flow_id != second_flow_id

    assert Jido.Exec.Node.Invoke.target_component_key(first_node, first_target_id) !=
             Jido.Exec.Node.Invoke.target_component_key(second_node, second_target_id)
  end

  @tag obligation: ["jido_action.boundary.I5", "jido_action.boundary.I8"]
  test "Invoke connection handles zero and multiple parents" do
    instruction = Instruction.new!(target: Decide)

    left =
      Jido.Exec.Node.Action.new(instruction,
        id: :left,
        name: "left"
      )

    right =
      Jido.Exec.Node.Action.new(instruction,
        id: :right,
        name: "right"
      )

    assert %Workflow{} =
             Jido.Exec.Node.Invoke.connect(invoke_node(:root), [], Workflow.new())

    workflow = Workflow.new() |> Workflow.add(left) |> Workflow.add(right)

    join =
      invoke_node(:join,
        location: {:file, 12, 4},
        node_path: ["outer", "next"]
      )

    assert %Workflow{} =
             connected =
             Jido.Exec.Node.Invoke.connect(
               join,
               [left, right],
               workflow
             )

    decision =
      Enum.find(Multigraph.vertices(connected.graph), fn
        %Jido.Exec.Node.Action{flow: %{mode: {:invoke, :decision}}} -> true
        _node -> false
      end)

    assert %Jido.Exec.Node.Action{
             flow: %{
               component: "next",
               mode: {:invoke, :decision},
               location: {:file, 12, 4},
               node_path: ["outer", "next"]
             }
           } = decision
  end

  @tag obligation: ["jido_action.boundary.I2", "jido_action.boundary.I8"]
  test "Invoke Finish projects invalid target input as a failed result" do
    finish = Jido.Exec.Node.Invoke.Finish.new(invoke_node(:failure), "target")

    assert %Runic.Workflow.SingleOutput.Result{
             status: :failure,
             error: %{details: %{reason: :invalid_flow_frame}}
           } =
             Jido.Exec.Node.Invoke.Finish.run(
               finish,
               Jido.Exec.Fact.local_value(:invalid),
               %Runic.Workflow.SingleOutput.Context{}
             )
  end

  @tag obligation: "jido_action.boundary.I8"
  test "a direct expander result does not create a Call" do
    {completed, observation} =
      flow()
      |> Exec.compile!()
      |> Workflow.execute(Jido.Exec.Fact.local_value(Frame.new(%{mode: "finish", value: 4})))

    assert Exec.result(completed, observation) == {:ok, %{final: 4}, [:expander]}
    refute Enum.any?(Multigraph.vertices(completed.graph), &is_struct(&1, Runic.Workflow.Call))
  end

  @tag obligation: "jido_action.boundary.I8"
  test "downstream components run after the Invoke completion gate" do
    flow =
      Flow.new!(%{
        name: "invoke_downstream",
        components: [
          %{
            kind: :invoke,
            name: "next",
            decision: Decide,
            expander: Expand,
            params: %{mode: "continue", value: Ref.input(:value)}
          },
          %{
            kind: :step,
            name: "after",
            action: Finalize,
            params: %{value: Ref.result("next", :final)}
          }
        ],
        output: Ref.result("after")
      })

    assert Exec.run(flow, %{value: 4}) == {:ok, %{final: 4}}
  end

  @tag obligation: "jido_action.boundary.I8"
  test "more than one Invoke can run when the static graph permits it" do
    flow =
      Flow.new!(%{
        name: "multiple_invokes",
        components: [
          %{
            kind: :invoke,
            name: "left",
            decision: Decide,
            expander: Expand,
            params: %{mode: "finish", value: Ref.input(:left)}
          },
          %{
            kind: :invoke,
            name: "right",
            decision: Decide,
            expander: Expand,
            params: %{mode: "finish", value: Ref.input(:right)}
          }
        ],
        output: %{left: Ref.result("left", :final), right: Ref.result("right", :final)}
      })

    assert Exec.run(flow, %{left: 1, right: 2}) ==
             {:ok, %{left: 1, right: 2}, [:expander, :expander]}
  end

  @tag obligation: "jido_action.boundary.I8"
  test "continued Invoke results join after both targets finish" do
    flow =
      Flow.new!(%{
        name: "continued_invoke_join",
        components: [
          %{
            kind: :invoke,
            name: "left",
            decision: Decide,
            expander: Expand,
            params: %{mode: "continue", value: Ref.input(:left)}
          },
          %{
            kind: :invoke,
            name: "right",
            decision: Decide,
            expander: Expand,
            params: %{mode: "continue", value: Ref.input(:right)}
          }
        ],
        output: %{left: Ref.result("left"), right: Ref.result("right")}
      })

    {completed, observation} =
      flow
      |> Exec.compile!()
      |> Workflow.execute(
        Jido.Exec.Fact.local_value(Frame.new(%{left: 1, right: 2})),
        max_concurrency: 1
      )

    assert Exec.result(completed, observation) ==
             {:ok, %{left: %{final: 1}, right: %{final: 2}}}

    target_nodes =
      Enum.filter(Multigraph.vertices(completed.graph), fn
        %Jido.Exec.Node.Action{flow: %{mode: {:invoke, :target}}} -> true
        _node -> false
      end)

    assert length(target_nodes) == 2
    assert length(Enum.uniq_by(target_nodes, & &1.id)) == 2
  end

  @tag obligation: ["jido_action.boundary.I5", "jido_action.boundary.I8"]
  test "a rebuilt mixed join waits for its continued Invoke target" do
    flow =
      Flow.new!(%{
        name: "rebuilt_mixed_invoke_join",
        components: [
          %{
            kind: :invoke,
            name: "next",
            decision: Decide,
            expander: Expand,
            params: %{mode: "continue", value: Ref.input(:dynamic)}
          },
          %{
            kind: :step,
            name: "static",
            action: Finalize,
            params: %{value: Ref.input(:static)}
          }
        ],
        output: %{dynamic: Ref.result("next"), static: Ref.result("static")}
      })

    rebuilt = flow |> Exec.compile!() |> Workflow.build_log() |> Workflow.from_log()

    {completed, observation} =
      Workflow.execute(
        rebuilt,
        Jido.Exec.Fact.local_value(Frame.new(%{dynamic: 3, static: 4})),
        max_concurrency: 1
      )

    assert Exec.result(completed, observation) ==
             {:ok, %{dynamic: %{final: 3}, static: %{final: 4}}}
  end

  @tag obligation: ["jido_action.boundary.I5", "jido_action.boundary.I8"]
  test "an Invoke joins more than one dependency before its decision" do
    flow =
      Flow.new!(%{
        name: "invoke_multiple_parents",
        components: [
          %{kind: :step, name: "left", action: Finalize, params: %{value: 2}},
          %{kind: :step, name: "right", action: Finalize, params: %{value: 3}},
          %{
            kind: :invoke,
            name: "next",
            decision: Combine,
            expander: Expand,
            params: %{
              left: Ref.result("left", :final),
              right: Ref.result("right", :final)
            }
          }
        ],
        output: Ref.result("next")
      })

    rebuilt = flow |> Exec.compile!() |> Workflow.build_log() |> Workflow.from_log()

    {completed, observation} =
      Workflow.execute(rebuilt, Jido.Exec.Fact.local_value(Frame.new(%{})))

    assert Exec.result(completed, observation) == {:ok, %{final: 5}, [:expander]}
  end

  for {kind, target} <- [action: BoundTarget, flow: BoundFlow] do
    @tag obligation: "jido_action.boundary.I8"
    test "a bound #{kind} Instruction keeps merged params and context" do
      instruction =
        Instruction.new!(
          target: unquote(target),
          params: %{amount: 10, source: :bound},
          context: %{tenant: "bound", shared: "bound"}
        )

      assert Exec.run(
               bound_flow(),
               %{target: instruction, value: 2},
               %{shared: "runtime"}
             ) ==
               {:ok, %{value: 12, source: :continuation, tenant: "bound", shared: "runtime"}}
    end
  end

  @tag obligation: "jido_action.boundary.I8"
  test "bound continuation data gives dynamic targets distinct identities" do
    definition = Exec.compile!(bound_flow())

    first_target = Instruction.new!(target: BoundTarget, params: %{amount: 10})
    second_target = Instruction.new!(target: BoundTarget, params: %{amount: 20})

    first_input =
      Jido.Exec.Fact.local_value(Frame.new(%{target: first_target, value: 1}))

    second_input =
      Jido.Exec.Fact.local_value(Frame.new(%{target: second_target, value: 1}))

    {first, first_scope} = Workflow.execute(definition, first_input)
    {second, second_scope} = Workflow.execute(first, second_input)

    assert Exec.result(first, first_scope) ==
             {:ok, %{value: 11, source: :continuation, tenant: nil, shared: nil}}

    assert Exec.result(second, second_scope) ==
             {:ok, %{value: 21, source: :continuation, tenant: nil, shared: nil}}

    target_nodes =
      Enum.filter(Multigraph.vertices(second.graph), fn
        %Jido.Exec.Node.Action{flow: %{mode: {:invoke, :target}}} -> true
        _node -> false
      end)

    assert length(Enum.uniq_by(target_nodes, & &1.id)) == 2
  end

  @tag obligation: "jido_action.boundary.I8"
  test "different continuation modules have distinct target identities" do
    definition = Exec.compile!(bound_flow())

    first_target = Instruction.new!(target: BoundTarget, params: %{amount: 10})
    second_target = Instruction.new!(target: AlternateBoundTarget, params: %{amount: 10})

    {first, first_scope} =
      Workflow.execute(
        definition,
        Jido.Exec.Fact.local_value(Frame.new(%{target: first_target, value: 2}))
      )

    {second, second_scope} =
      Workflow.execute(
        first,
        Jido.Exec.Fact.local_value(Frame.new(%{target: second_target, value: 2}))
      )

    assert Exec.result(first, first_scope) ==
             {:ok, %{value: 12, source: :continuation, tenant: nil, shared: nil}}

    assert Exec.result(second, second_scope) ==
             {:ok, %{value: 20, source: :continuation, target: :alternate}}

    target_nodes =
      Enum.filter(Multigraph.vertices(second.graph), fn
        %Jido.Exec.Node.Action{flow: %{mode: {:invoke, :target}}} -> true
        _node -> false
      end)

    assert length(target_nodes) >= 2

    assert MapSet.new(target_nodes, & &1.instruction.target) ==
             MapSet.new([BoundTarget, AlternateBoundTarget])
  end

  @tag obligation: "jido_action.boundary.I8"
  test "different runtime Flow values have distinct target identities" do
    definition = Exec.compile!(bound_flow())
    first_target = runtime_target_flow(11)
    second_target = runtime_target_flow(22)

    {first, first_scope} =
      Workflow.execute(
        definition,
        Jido.Exec.Fact.local_value(Frame.new(%{target: first_target, value: 0}))
      )

    {second, second_scope} =
      Workflow.execute(
        first,
        Jido.Exec.Fact.local_value(Frame.new(%{target: second_target, value: 0}))
      )

    assert Exec.result(first, first_scope) == {:ok, %{final: 11}}
    assert Exec.result(second, second_scope) == {:ok, %{final: 22}}
  end

  @tag obligation: "jido_action.boundary.I8"
  test "invalid call data for a bound continuation returns a structured error" do
    instruction = Instruction.new!(target: BoundTarget, params: %{amount: 10})

    flow =
      Flow.new!(%{
        name: "invalid_bound_continuation",
        components: [
          %{
            kind: :invoke,
            name: "next",
            decision: Decide,
            expander: ExpandInvalidBound,
            params: %{target: Ref.input(:target)}
          }
        ],
        output: Ref.result("next")
      })

    assert {:error, %InvalidInputError{details: details}} =
             Exec.run(flow, %{target: instruction})

    assert details.node == "next"
    assert details.node_path == ["next"]
  end

  @tag obligation: "jido_action.boundary.I8"
  test "an Invoke expander cannot hand off" do
    flow =
      Flow.new!(%{
        name: "invoke_cannot_handoff",
        components: [
          %{kind: :invoke, name: "next", decision: Decide, expander: HandoffAttempt}
        ],
        output: Ref.result("next")
      })

    assert {:error, %{details: %{reason: :unsupported_handoff}}} = Exec.run(flow)
  end

  @tag obligation: [
         "jido_action.boundary.I1",
         "jido_action.boundary.I3",
         "jido_action.boundary.I8"
       ]
  test "selected Action validation failures keep their Flow location" do
    for {mode, value, context} <- [
          {"invalid_input", "bad", "Action"},
          {"invalid_output", 4, "Action output"}
        ] do
      assert {:error, %InvalidInputError{details: details}} =
               Exec.run(flow(), %{mode: mode, value: value})

      assert details.node == "next"
      assert details.node_path == ["next"]
      assert details.context == context
    end
  end

  @tag obligation: ["jido_action.boundary.I2", "jido_action.boundary.I8"]
  test "selected Action failures return no executable effects" do
    assert {:error, %ExecutionFailureError{details: %{node: "next", reason: :bad_with_extras}}} =
             Exec.run(flow(), %{mode: "target_error", value: 4})
  end

  @tag obligation: "jido_action.boundary.I8"
  test "an invalid continuation target fails the expander Runnable" do
    assert {:error, %ConfigurationError{details: details}} =
             Exec.run(flow(), %{mode: "bad_target", value: 1})

    assert details.target == Enum
    assert details.node == "next"
    assert details.phase == :invoke
  end

  @tag obligation: "jido_action.boundary.I8"
  test "a selected wait target needs a wait-capable execution host" do
    assert {:error,
            %ConfigurationError{
              message: "execution host does not support waits",
              details: %{reason: :unsupported_host, capability: :waits}
            }} = Exec.run(flow(), %{mode: "runtime_wait", value: 1})
  end

  @tag obligation: "jido_action.boundary.I8"
  test "expander errors with discarded effects keep the Action reason" do
    assert {:error, %ExecutionFailureError{message: "expander refused"}} =
             Exec.run(flow(), %{mode: "refuse", value: 0})
  end

  @tag obligation: "jido_action.boundary.I8"
  test "expander effects must be a proper list" do
    assert {:error, %ExecutionFailureError{details: %{reason: :invalid_effects}}} =
             Exec.run(flow(), %{mode: "improper", value: 0})
  end

  defp flow do
    Flow.new!(%{
      name: "invoke_test",
      components: [
        %{
          kind: :invoke,
          name: "next",
          decision: Decide,
          expander: Expand,
          params: %{mode: Ref.input(:mode), value: Ref.input(:value)}
        }
      ],
      output: Ref.result("next")
    })
  end

  defp bound_flow do
    Flow.new!(%{
      name: "bound_invoke_test",
      components: [
        %{
          kind: :invoke,
          name: "next",
          decision: Decide,
          expander: ExpandBound,
          params: %{target: Ref.input(:target), value: Ref.input(:value)}
        }
      ],
      output: Ref.result("next")
    })
  end

  defp runtime_target_flow(value) do
    Flow.new!(%{
      name: "runtime_identity_target",
      components: [
        %{kind: :step, name: "finalize", action: Finalize, params: %{value: value}}
      ],
      output: Ref.result("finalize")
    })
  end

  defp invoke_node(id, opts \\ []) do
    Jido.Exec.Node.Invoke.new(
      [
        id: id,
        name: "next_#{id}",
        component: "next",
        decision: Instruction.new!(target: Decide),
        expander: Instruction.new!(target: Expand)
      ] ++ opts
    )
  end
end
