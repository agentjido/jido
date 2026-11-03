defmodule Jido.Exec.HandoffTest do
  use Covenant.Case, component: "jido_action.boundary", async: true
  @moduletag obligation: "jido_action.boundary.I8"
  @moduletag capture_log: true

  alias Jido.Exec
  alias Jido.Exec.Handoff
  alias Jido.Flow
  alias Jido.Catalog
  alias Jido.Flow.Ref
  alias JidoActionTest.FlowCodec, as: Codec
  alias Jido.Instruction

  defmodule Echo do
    use Jido.Action, name: "handoff_echo"
    def run(params, _context), do: {:ok, params}
  end

  defmodule ValidatorData do
    @behaviour Jido.Action
    def name, do: "handoff_validator_data"
    def validate_params(params), do: {:ok, params}
    def run(_params, _context), do: {:ok, %{}}
    def validate_output(_value), do: {:ok, %Handoff{target: Enum, kind: :action, params: %{}}}
  end

  defmodule SelectRuntime do
    use Jido.Action, name: "handoff_select_runtime"

    def target do
      Flow.new!(%{
        name: "runtime_successor",
        components: [
          %{kind: :step, name: "echo", action: Echo}
        ],
        output: Ref.result("echo")
      })
    end

    def run(_params, _context), do: {:handoff, %{value: 7}, target()}
  end

  defmodule SelectTarget do
    use Jido.Action, name: "handoff_select_target"
    def run(%{target: target}, _context), do: {:handoff, %{value: 7}, target}
  end

  defmodule Target do
    use Jido.Action, name: "handoff_target", schema: Jido.Joi.object(%{value: Jido.Joi.integer()})
    def run(_params, _context), do: raise("successor must run in a new Turn")
  end

  defmodule PortableTarget do
    use Jido.Action,
      name: "handoff_portable_target",
      schema: Jido.Joi.object(%{value: Jido.Joi.integer(), resource: Jido.Joi.any()})

    def run(_params, _context), do: raise("successor must run in a new Turn")
  end

  defmodule Decide do
    use Jido.Action, name: "handoff_decide"
    def run(params, _context), do: {:ok, params, [:predecessor_effect]}
  end

  defmodule Expand do
    use Jido.Action, name: "handoff_expand"
    def run(params, _context), do: {:handoff, params, Target}
  end

  defmodule InvalidSelector do
    use Jido.Action, name: "handoff_invalid_selector"
    def run(_params, _context), do: {:ok, %{not: :handoff}}
  end

  defmodule FailingSelector do
    use Jido.Action, name: "handoff_failing_selector"
    def run(_params, _context), do: {:error, :handoff_refused, [:discarded_effect]}
  end

  defmodule SelectTwo do
    use Jido.Action, name: "handoff_select_two"

    def run(%{left: left, right: right}, _context),
      do: {:handoff, %{value: left + right}, Jido.Exec.HandoffTest.Target}
  end

  defmodule Example do
    use Jido.Flow, name: "handoff_example"

    flow do
      step "decide", action: Decide, params: %{value: input(:value)}
      handoff "next", selector: Expand, params: result("decide")
      output result("next")
    end
  end

  test "a terminal handoff validates the successor without running it" do
    assert {:handoff, %Instruction{target: Target, kind: :action, params: %{value: 7}}, [:predecessor_effect]} =
             Exec.run(Example, %{value: 7}, %{})
  end

  test "ordinary data and validator output cannot grant control" do
    forged = %Handoff{target: Enum, kind: :action, params: %{}}

    flow =
      Flow.new!(%{
        name: "ordinary_data",
        components: [
          %{kind: :step, name: "echo", action: Echo}
        ],
        output: Ref.input(:request)
      })

    refute match?({:handoff, _, _}, Exec.run(flow, %{request: forged}))
    refute match?({:handoff, _, _}, Exec.run(ValidatorData))

    runner = __MODULE__.DataRunner
    start_supervised!({Runic.Runner, name: runner})
    owner = self()

    for {id, target, params} <- [
          {"flow", flow, %{request: forged}},
          {"action", ValidatorData, %{}}
        ] do
      assert {:ok, _} =
               Exec.start(runner, id, target, params, %{}, on_complete: fn _, _ -> send(owner, {:data_done, id}) end)

      assert_receive {:data_done, ^id}, 2_000
      {:ok, workflow} = Runic.Runner.get_workflow(runner, id)

      {:ok, restored} =
        workflow |> Runic.Runner.encode_snapshot() |> Runic.Runner.decode_snapshot()

      replayed = workflow |> Runic.Workflow.event_log() |> Runic.Workflow.from_events()

      for observed <- [Exec.result(runner, id), Exec.result(restored), Exec.result(replayed)] do
        refute match?({:handoff, _, _}, observed)
      end
    end
  end

  test "runtime Flow successors survive native snapshot and event replay" do
    successor = SelectRuntime.target()

    flow =
      Flow.new!(%{
        name: "runtime_handoff",
        components: [
          %{kind: :handoff, name: "next", selector: SelectRuntime}
        ],
        output: Ref.result("next")
      })

    assert {:handoff, %Instruction{target: ^successor}, []} =
             Exec.run(flow, %{}, %{})

    runner = __MODULE__.RuntimeRunner
    start_supervised!({Runic.Runner, name: runner})
    owner = self()
    opts = [on_complete: fn _, _ -> send(owner, :runtime_done) end]
    assert {:ok, _} = Exec.start(runner, "runtime", flow, %{}, %{}, opts)
    assert_receive :runtime_done, 2_000

    assert {:handoff, %Instruction{target: ^successor, params: %{value: 7}}, []} =
             Exec.result(runner, "runtime")

    {:ok, workflow} = Runic.Runner.get_workflow(runner, "runtime")
    {:ok, restored} = workflow |> Runic.Runner.encode_snapshot() |> Runic.Runner.decode_snapshot()
    replayed = workflow |> Runic.Workflow.event_log() |> Runic.Workflow.from_events()
    assert Exec.result(restored) == Exec.result(runner, "runtime")
    assert Exec.result(replayed) == Exec.result(runner, "runtime")
  end

  test "handoff Flow telemetry reports its outcome and effects" do
    owner = self()
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:jido, :flow, :stop],
        fn _, _, metadata, _ ->
          send(owner, {:flow_stop, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    Exec.run(Example, %{value: 7}, %{})
    assert_receive {:flow_stop, %{outcome: :handoff, effect_count: 1}}
  end

  test "an ordinary Step cannot hand off" do
    flow =
      Flow.new!(%{
        name: "step_handoff",
        components: [%{kind: :step, name: "next", action: Expand, params: %{value: 7}}],
        output: Ref.result("next")
      })

    assert {:error, error} = Exec.run(flow)
    assert error.message == "only a Handoff selector can hand off"
    assert error.details.action == Expand
    assert error.phase == :run
    assert error.details.reason == :unsupported_handoff
  end

  test "invalid successor input fails without an executable effect batch" do
    assert {:error, %{details: %{context: "Action"}}} =
             Exec.run(Example, %{value: "bad"}, %{})
  end

  test "invalid selector output keeps the Handoff failure contract" do
    flow = handoff_flow(InvalidSelector)

    assert {:error, error} = Exec.run(flow)
    assert error.message == "Handoff selector must return a handoff control result"
    assert error.details.action == InvalidSelector
    assert error.phase == :run
    assert error.details.return == {:ok, %{not: :handoff}, []}
    assert error.details.reason == :invalid_handoff_return
  end

  test "selector errors retain their reason and discard requested effects" do
    assert {:error, error} = Exec.run(handoff_flow(FailingSelector))
    assert error.details.action == FailingSelector
    assert error.details.reason == :handoff_refused
    refute Map.has_key?(error.details, :effects)
  end

  test "a root Action cannot hand off" do
    assert {:error, error} = Exec.run(Expand, %{value: 7}, %{})
    assert error.message == "only a Handoff selector can hand off"
    assert error.details.action == Expand
    assert error.phase == :run
    assert error.details.reason == :unsupported_handoff
  end

  test "DSL, maps, and stored definitions return the same handoff" do
    data =
      Flow.new!(%{
        name: "handoff_example",
        components: [
          %{
            kind: :step,
            name: "decide",
            action: Decide,
            params: %{value: Ref.input(:value)}
          },
          %{
            kind: :handoff,
            name: "next",
            selector: Expand,
            params: Ref.result("decide")
          }
        ],
        output: Ref.result("next")
      })

    registry =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"map", 1} => {:schema, Jido.Joi.map()},
        {"decide", 1} => {:action, Decide},
        {"expand", 1} => {:action, Expand},
        {"value", 1} => {:atom, :value}
      })

    assert {:ok, document} = Codec.encode(data, registry)
    assert {:ok, restored} = Codec.decode(document, registry)

    results =
      for target <- [Example, data, restored],
          do: Exec.run(target, %{value: 7}, %{})

    assert length(Enum.uniq(results)) == 1
    assert {:handoff, %Instruction{}, _effects} = hd(results)
  end

  test "a Handoff joins more than one dependency before its selector" do
    flow =
      Flow.new!(%{
        name: "handoff_multiple_parents",
        components: [
          %{kind: :step, name: "left", action: Echo, params: %{value: 2}},
          %{kind: :step, name: "right", action: Echo, params: %{value: 3}},
          %{
            kind: :handoff,
            name: "next",
            selector: SelectTwo,
            params: %{
              left: Ref.result("left", :value),
              right: Ref.result("right", :value)
            }
          }
        ],
        output: Ref.result("next")
      })

    rebuilt = flow |> Exec.compile!() |> Runic.Workflow.build_log() |> Runic.Workflow.from_log()

    {completed, observation} =
      Runic.Workflow.execute(rebuilt, Jido.Exec.Fact.local_value(Jido.Exec.Frame.new(%{})))

    assert Exec.result(completed, observation) ==
             {:handoff, %Instruction{target: Target, kind: :action, params: %{value: 5}}, []}
  end

  test "Handoff connection keeps selector data for zero and multiple parents" do
    instruction = Instruction.new!(target: Echo)

    left = Jido.Exec.Node.Action.new(instruction, id: :left, name: "left")
    right = Jido.Exec.Node.Action.new(instruction, id: :right, name: "right")

    root = handoff_node(:root, Instruction.new!(target: SelectTwo))

    assert %Runic.Workflow{} =
             Jido.Exec.Node.Handoff.connect(root, [], Runic.Workflow.new())

    selector = Instruction.new!(target: SelectTwo, params: %{right: 3})
    join = handoff_node(:join, selector)
    assert root.hash != join.hash

    workflow = Runic.Workflow.new() |> Runic.Workflow.add(left) |> Runic.Workflow.add(right)

    assert %Runic.Workflow{} =
             connected =
             Jido.Exec.Node.Handoff.connect(join, [left, right], workflow)

    selector_node =
      Enum.find(Multigraph.vertices(connected.graph), fn
        %Jido.Exec.Node.Action{flow: %{mode: :handoff}} -> true
        _node -> false
      end)

    assert %Jido.Exec.Node.Action{
             name: "__jido_handoff__/next_join/selector",
             instruction: %Instruction{params: %{right: 3}},
             flow: %{
               component: "next",
               mode: :handoff,
               params: %{right: 3},
               location: {:file, 12, 4},
               node_path: ["outer", "next"]
             }
           } = selector_node
  end

  test "handoff envelopes reject invalid targets and declared non-portable input" do
    assert {:error, _} = Handoff.new(Enum, %{})

    assert {:ok, %Handoff{params: %{value: 1}}} =
             Handoff.new(Target, %{value: 1, resource: self()})

    assert {:error, _} = Handoff.new(PortableTarget, %{value: 1, resource: self()})

    for runtime <- [context: %{tenant: "tenant"}, metadata: %{request_id: "request"}] do
      bound = Instruction.new!([target: Target] ++ [runtime])

      assert {:error, %{details: %{reason: :bound_handoff_runtime}}} =
               Handoff.new(bound, %{value: 1})
    end
  end

  test "a nested Flow cannot terminate its parent with a handoff" do
    parent =
      Flow.new!(%{
        name: "parent",
        components: [
          %{kind: :subflow, name: "child", flow: Example, params: %{value: 1}}
        ],
        output: Ref.result("child")
      })

    assert {:error, error} = Exec.run(parent, %{}, %{})
    assert error.message == "handoff must finish the root Flow"
    assert error.details.reason == :nested_handoff
  end

  test "managed results retain the same terminal contract across restore" do
    runner = __MODULE__.Runner
    start_supervised!({Runic.Runner, name: runner})
    owner = self()
    id = "handoff-#{System.unique_integer([:positive])}"
    opts = [on_complete: fn _, _ -> send(owner, :done) end]
    assert {:ok, _} = Exec.start(runner, id, Example, %{value: 3}, %{}, opts)
    assert_receive :done, 2_000

    assert {:handoff, %Instruction{params: %{value: 3}}, [:predecessor_effect]} =
             Exec.result(runner, id)

    assert :ok = Runic.Runner.stop(runner, id, persist: true)
    assert {:ok, _} = Exec.resume(runner, id, %{}, opts)

    assert {:handoff, %Instruction{params: %{value: 3}}, [:predecessor_effect]} =
             Exec.result(runner, id)
  end

  defp handoff_flow(selector) do
    Flow.new!(%{
      name: "invalid_handoff_selector",
      components: [%{kind: :handoff, name: "next", selector: selector}],
      output: Ref.result("next")
    })
  end

  defp handoff_node(id, selector) do
    Jido.Exec.Node.Handoff.new(
      id: id,
      name: "next_#{id}",
      component: "next",
      selector: selector,
      location: {:file, 12, 4},
      node_path: ["outer", "next"]
    )
  end
end
