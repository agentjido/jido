defmodule Jido.Exec.WaitsTest do
  use Covenant.Case, component: "jido_action.execution", async: true
  @moduletag obligation: "jido_action.execution.I25"
  @moduletag capture_log: true
  alias Jido.Exec.Test.WaitHost, as: Waits
  alias Jido.Flow
  alias Jido.Flow.Ref

  defp flow do
    Flow.new!(%{
      name: "wait_example",
      components: [
        %{kind: :timer, name: "delay", after_ms: 7_776_000_000},
        %{
          kind: :await,
          name: "approval",
          event: "approved",
          match: %{id: Ref.input(:id)},
          needs: ["delay"]
        }
      ],
      output: Ref.result("approval")
    })
  end

  defmodule ReadCapabilities do
    use Jido.Action, name: "read_execution_capabilities"

    @impl Jido.Action
    def run(_params, context) do
      {:ok,
       %{
         capabilities: Map.get(context, :jido_exec_capabilities, []),
         trace_id: Map.get(context, :trace_id),
         waits?: Jido.Exec.supports?(context, :waits)
       }}
    end
  end

  defmodule CapabilityFlow do
    use Jido.Flow, name: "nested_capability_flow"

    flow do
      step "read", action: Jido.Exec.WaitsTest.ReadCapabilities, params: %{}
      output result("read")
    end
  end

  defmodule SelectCapabilities do
    use Jido.Action, name: "select_nested_capabilities"

    @impl Jido.Action
    def run(params, _context), do: {:ok, params}
  end

  defmodule ExpandCapabilities do
    use Jido.Action, name: "expand_nested_capabilities"

    @impl Jido.Action
    def run(_params, _context),
      do: {:continue, %{}, Jido.Exec.WaitsTest.CapabilityFlow}
  end

  defmodule ExpandForgedCapabilities do
    use Jido.Action, name: "expand_forged_capabilities"

    @impl Jido.Action
    def run(_params, _context) do
      target =
        Jido.Instruction.new!(
          kind: :flow,
          target: Jido.Exec.WaitsTest.CapabilityFlow,
          context: %{__jido_wait_host__: :forged}
        )

      {:continue, %{}, target}
    end
  end

  defp capability_invoke(expander) do
    Flow.new!(%{
      name: "nested_capability_invoke",
      components: [
        %{
          kind: :invoke,
          name: "invoke",
          decision: SelectCapabilities,
          expander: expander
        }
      ],
      output: Ref.result("invoke")
    })
  end

  test "Actions can read stable execution host capabilities" do
    assert {:ok, %{capabilities: [], trace_id: nil, waits?: false}} =
             Jido.Exec.run(ReadCapabilities)

    assert {:ok, workflow} = Waits.start("capabilities", ReadCapabilities, %{}, %{}, now: 0)

    assert {:complete, {:ok, %{capabilities: [:waits], trace_id: nil, waits?: true}}} =
             Waits.status(workflow)
  end

  test "caller context cannot claim execution host capabilities" do
    for {key, value} <- [
          {:jido_exec_capabilities, [:waits]},
          {:__jido_wait_host__, :forged}
        ] do
      context = Map.put(%{trace_id: "kept"}, key, value)

      assert {:ok, %{capabilities: [], trace_id: "kept", waits?: false}} =
               Jido.Exec.run(ReadCapabilities, %{}, context)
    end
  end

  test "bound Invoke target context cannot claim host capabilities" do
    assert {:ok, %{capabilities: [], trace_id: nil, waits?: false}} =
             ExpandForgedCapabilities
             |> capability_invoke()
             |> Jido.Exec.run()
  end

  test "supports? returns false for malformed capability data" do
    for value <- [nil, :waits, %{}, "waits", 1, [:waits | :invalid], [:other | :invalid]] do
      refute Jido.Exec.supports?(%{jido_exec_capabilities: value}, :waits)
    end

    assert Jido.Exec.supports?(%{jido_exec_capabilities: [:waits]}, :waits)
    refute Jido.Exec.supports?(%{jido_exec_capabilities: [:waits]}, :unknown)
    assert_raise FunctionClauseError, fn -> apply(Jido.Exec, :supports?, [[], :waits]) end
  end

  test "nested Invoke and Flow Actions retain genuine host capabilities" do
    flow = capability_invoke(ExpandCapabilities)

    assert {:ok, %{capabilities: [], trace_id: "direct", waits?: false}} =
             Jido.Exec.run(flow, %{}, %{trace_id: "direct"})

    assert {:ok, workflow} =
             Waits.start("nested-capabilities", flow, %{}, %{trace_id: "host"}, now: 0)

    assert {:complete, {:ok, %{capabilities: [:waits], trace_id: "host", waits?: true}}} =
             Waits.status(workflow)
  end

  test "a 90-day wait releases work and saves an absolute deadline" do
    assert {:ok, workflow} = Waits.start("run-1", flow(), %{id: 7}, %{}, now: 100)
    assert {:waiting, [request]} = Waits.status(workflow)
    assert request.deadline == 7_776_000_100
    refute Runic.Workflow.is_runnable?(workflow)

    assert {:ok, restored} =
             workflow |> Runic.Runner.encode_snapshot() |> Runic.Runner.decode_snapshot()

    assert Waits.status(restored) == Waits.status(workflow)
    assert {:ok, workflow} = Waits.advance(restored, %{}, now: request.deadline)
    assert {:waiting, [%{event: "approved", match: %{id: 7}} = approval]} = Waits.status(workflow)

    assert {:ok, workflow} =
             Waits.accept(
               workflow,
               %{
                 id: "input-1",
                 wait_id: approval.id,
                 event: "approved",
                 payload: %{id: 7, approved: true}
               },
               %{},
               now: request.deadline
             )

    assert {:complete, {:ok, %{id: 7, approved: true}}} = Waits.status(workflow)
  end

  test "ordinary Exec rejects wait definitions before work starts" do
    assert {:error, %{details: %{reason: :unsupported_host, capability: :waits}}} =
             Jido.Exec.run(flow(), %{id: 7})
  end

  defmodule SelectionFlow do
    use Jido.Flow, name: "selection_example"

    flow do
      selection "decision" do
        await "approved", event: "approved", match: %{id: input(:id)}
        await "rejected", event: "rejected"
        timer "expired", after_ms: 10
      end

      output result("decision")
    end
  end

  defmodule TimerFlow do
    use Jido.Flow, name: "timer_example"

    flow do
      timer "delay", after_ms: 10
      await "approval", event: "approved", needs: ["delay"]
      output result("approval")
    end
  end

  test "DSL, data and Codec share one wait model" do
    data =
      Flow.new!(%{
        name: "selection_example",
        components: [
          %{
            kind: :selection,
            name: "decision",
            options: [
              %{kind: :await, name: "approved", event: "approved", match: %{id: Ref.input(:id)}},
              %{kind: :await, name: "rejected", event: "rejected"},
              %{kind: :timer, name: "expired", after_ms: 10}
            ]
          }
        ],
        output: Ref.result("decision")
      })

    assert data == SelectionFlow.flow()

    registry =
      Jido.Authoring.Registry.new!(%{
        {"map", 1} => {:schema, Zoi.map()},
        {"id", 1} => {:atom, :id}
      })

    assert {:ok, encoded} = JidoActionTest.FlowCodec.encode(data, registry)
    assert {:ok, restored} = JidoActionTest.FlowCodec.decode(encoded, registry)
    assert restored == data

    for target <- [SelectionFlow, data, restored] do
      assert {:ok, wf} = Waits.start("selection", target, %{id: 2}, %{}, now: 100)
      assert {:waiting, [request]} = Waits.status(wf)
      assert {:ok, wf} = Waits.accept(wf, event(request, "approved", %{id: 2}), %{}, now: 105)

      assert {:complete, {:ok, %{selected: "approved", value: %{id: 2}, accepted_at: 105}}} =
               Waits.status(wf)
    end
  end

  test "a timer wins an equal-time input and removes all losing waits" do
    {:ok, wf} = Waits.start("race", SelectionFlow, %{id: 1}, %{}, now: 0)
    {:waiting, [request]} = Waits.status(wf)
    input = event(request, "approved", %{id: 1})
    assert {:ok, wf} = Waits.accept(wf, input, %{}, now: 10)
    assert {:complete, {:ok, %{selected: "expired", value: %{fired_at: 10}}}} = Waits.status(wf)
    assert {:ok, ^wf} = Waits.accept(wf, input, %{}, now: 11)

    assert {:error, %{details: %{reason: :stale_target}}} =
             Waits.accept(wf, %{input | id: "late"}, %{}, now: 11)

    restored = restore(wf)
    assert Waits.status(restored) == Waits.status(wf)
  end

  test "duplicate input IDs are inert and conflicting IDs fail" do
    {:ok, wf} = Waits.start("duplicate", SelectionFlow, %{id: 1}, %{}, now: 0)
    {:waiting, [request]} = Waits.status(wf)
    input = event(request, "approved", %{id: 1})
    assert {:ok, wf} = Waits.accept(wf, input, %{}, now: 1)
    wf = restore(wf)
    assert {:ok, ^wf} = Waits.accept(wf, input, %{}, now: 2)

    assert {:error, %{details: %{reason: :conflicting_input_id}}} =
             Waits.accept(wf, %{input | payload: %{id: 2}}, %{}, now: 2)
  end

  test "early addressed input survives restore and is consumed once" do
    {:ok, wf} = Waits.start("early", TimerFlow, %{}, %{}, now: 0)
    input = %{id: "early", path: ["approval"], event: "approved", payload: %{ok: true}}
    assert {:ok, wf} = Waits.accept(wf, input, %{}, now: 1)
    wf = restore(wf)
    assert {:waiting, [%{deadline: 10}]} = Waits.status(wf)
    assert {:ok, wf} = Waits.advance(wf, %{}, now: 10)
    assert {:complete, {:ok, %{ok: true}}} = Waits.status(wf)
  end

  test "buffers are bounded and expired early input does not consume capacity" do
    {:ok, wf} = Waits.start("bounded", TimerFlow, %{}, %{}, now: 0, max_buffered_inputs: 1)
    input = %{id: "one", path: ["approval"], event: "other", payload: %{}, expires_at: 2}
    assert {:ok, wf} = Waits.accept(wf, input, %{}, now: 1)

    assert {:error, %{details: %{reason: :buffer_full}}} =
             Waits.accept(wf, %{input | id: "two"}, %{}, now: 1)

    assert {:error, %{details: %{reason: :expired_input}}} =
             Waits.accept(wf, %{input | id: "expired"}, %{}, now: 2)

    assert {:ok, wf} = Waits.accept(wf, %{input | id: "three", expires_at: 20}, %{}, now: 3)
    assert {:ok, wf} = Waits.advance(wf, %{}, now: 10)
    assert {:waiting, [%{event: "approved"}]} = Waits.status(wf)
  end

  test "cancelled snapshots reject input and all future deadlines" do
    {:ok, wf} = Waits.start("cancel", SelectionFlow, %{id: 1}, %{}, now: 0)
    {:waiting, [request]} = Waits.status(wf)
    assert {:ok, wf} = Waits.cancel(wf)
    wf = restore(wf)
    assert Waits.status(wf) == :cancelled
    assert {:ok, ^wf} = Waits.cancel(wf)
    assert {:error, %{details: %{reason: :cancelled}}} = Waits.advance(wf, %{}, now: 20)

    assert {:error, %{details: %{reason: :cancelled}}} =
             Waits.accept(wf, event(request, "approved", %{id: 1}), %{}, now: 1)
  end

  test "wait IDs include the execution occurrence" do
    {:ok, first} = Waits.start("first", SelectionFlow, %{id: 1}, %{}, now: 0)
    {:ok, second} = Waits.start("second", SelectionFlow, %{id: 1}, %{}, now: 0)
    {:waiting, [a]} = Waits.status(first)
    {:waiting, [b]} = Waits.status(second)
    refute a.id == b.id

    assert {:error, %{details: %{reason: :stale_target}}} =
             Waits.accept(second, event(a, "approved", %{id: 1}), %{}, now: 1)
  end

  test "invalid clocks, non-portable inputs, and malformed definitions fail" do
    for opts <- [[], [now: -1], [now: :bad], [now: 0, extra: true]] do
      assert {:error, _} = Waits.start("invalid", TimerFlow, %{}, %{}, opts)
    end

    {:ok, wf} = Waits.start("clock", TimerFlow, %{}, %{}, now: 10)

    assert {:error, %{details: %{reason: :clock_moved_backwards}}} =
             Waits.advance(wf, %{}, now: 9)

    assert {:error, _} = Waits.accept(wf, %{id: "bad"}, %{}, now: 10)
    assert {:error, _} = Waits.start("resource", TimerFlow, %{pid: self()}, %{}, now: 0)

    for component <- [
          %{kind: :timer, name: "bad", after_ms: -1},
          %{kind: :await, name: "bad", event: ""},
          %{kind: :selection, name: "bad", options: []}
        ] do
      assert {:error, _} =
               Flow.new(%{name: "invalid", components: [component], output: Ref.result("bad")})
    end
  end

  test "native event replay retains pending waits and accepted results" do
    {:ok, wf} = Waits.start("events", SelectionFlow, %{id: 1}, %{}, now: 0)
    restored = Runic.Workflow.from_events(Runic.Workflow.event_log(wf))
    assert Waits.status(restored) == Waits.status(wf)
    {:waiting, [request]} = Waits.status(restored)
    assert {:ok, done} = Waits.accept(restored, event(request, "approved", %{id: 1}), %{}, now: 1)
    replayed = Runic.Workflow.from_events(Runic.Workflow.event_log(done))
    assert Waits.status(replayed) == Waits.status(done)
  end

  defp event(request, name, payload),
    do: %{id: "input", wait_id: request.id, event: name, payload: payload}

  defp restore(workflow) do
    assert {:ok, restored} =
             workflow |> Runic.Runner.encode_snapshot() |> Runic.Runner.decode_snapshot()

    restored
  end
end
