defmodule Jido.Exec.ComposedWaitsTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true
  alias Jido.Exec.Test.WaitHost, as: Waits
  alias Jido.Exec.Test.WaitStore.Memory
  alias Jido.Flow
  alias Jido.Flow.Ref

  defmodule Record do
    use Jido.Action, name: "record_before_wait"

    def run(%{id: id}, %{counter: counter}) do
      Agent.update(counter, &[id | &1])
      {:ok, %{id: id}, [%{recorded: id}]}
    end
  end

  defmodule Child do
    use Jido.Flow, name: "waiting_child"

    flow do
      step "done", action: Record, params: %{id: input(:id)}
      await "approval", event: "approved", match: %{id: input(:id)}, needs: ["done"]
      output result("approval")
    end
  end

  defmodule Decide do
    use Jido.Action, name: "select_waiting_flow"

    def run(params, %{controls: controls}) do
      Agent.update(controls, &[:decision | &1])
      {:ok, params}
    end
  end

  defmodule TimerChild do
    use Jido.Flow, name: "timer_child"

    flow do
      step "done", action: Record, params: %{id: input(:id)}
      timer "delay", after_ms: 10, needs: ["done"]
      output result("delay")
    end
  end

  defmodule Expand do
    use Jido.Action, name: "expand_waiting_flow"

    def run(params, %{controls: controls}) do
      Agent.update(controls, &[:expand | &1])
      target = if params.id == -1, do: TimerChild, else: Child
      {:continue, params, target}
    end
  end

  defmodule InvokeFlow do
    use Jido.Flow, name: "invoke_wait"

    flow do
      invoke "next", decision: Decide, expander: Expand, params: %{id: input(:id)}
      output result("next")
    end
  end

  defmodule Successor do
    use Jido.Action, name: "wait_successor"
    def run(_params, _context), do: raise("successor must use a new host execution")
  end

  defmodule HandoffExpand do
    use Jido.Action, name: "wait_handoff_expander"

    def run(params, %{controls: controls}) do
      Agent.update(controls, &[:handoff | &1])
      {:handoff, params, Successor}
    end
  end

  defmodule WaitThenHandoff do
    use Jido.Flow, name: "wait_then_handoff"

    flow do
      step "prepared", action: Record, params: %{id: input(:id)}
      await "approval", event: "approved", match: %{id: input(:id)}, needs: ["prepared"]

      step "decision",
        action: Decide,
        params: %{id: input(:id)},
        needs: ["approval"]

      handoff "next", selector: HandoffExpand, params: result("decision")

      output result("next")
    end
  end

  setup do
    start_supervised!(%{
      id: __MODULE__.Counter,
      start: {Agent, :start_link, [fn -> [] end, [name: __MODULE__.Counter]]}
    })

    start_supervised!(%{
      id: __MODULE__.Controls,
      start: {Agent, :start_link, [fn -> [] end, [name: __MODULE__.Controls]]}
    })

    %{context: %{counter: __MODULE__.Counter, controls: __MODULE__.Controls}}
  end

  test "the wait-to-handoff proof preserves save retries, duplicate input, and cancellation", %{
    context: ctx
  } do
    store = Memory.new()

    {:ok, waiting} =
      Waits.start("handoff", WaitThenHandoff, %{id: 10}, ctx, now: 0)

    assert {:ok, 1} = Memory.save("handoff", 0, waiting, store)
    {:ok, 1, restored} = Memory.load("handoff", store)
    {:waiting, [request]} = Waits.status(restored)
    input = event(request, "accepted", 10)
    {:ok, done} = Waits.accept(restored, input, ctx, now: 1)
    assert {:ok, 2} = Memory.save("handoff", 1, done, store)
    assert {:ok, 2} = Memory.save("handoff", 1, done, store)
    {:ok, 2, completed} = Memory.load("handoff", store)

    assert {:complete, {:handoff, %Jido.Instruction{target: Successor, params: %{id: 10}}, [%{recorded: 10}]}} =
             Waits.status(completed)

    assert {:ok, ^completed} =
             Waits.accept(completed, input, ctx, now: 2)

    replayed = completed |> Runic.Workflow.event_log() |> Runic.Workflow.from_events()
    assert Waits.status(replayed) == Waits.status(completed)
    assert Agent.get(__MODULE__.Counter, & &1) == [10]
    assert Agent.get(__MODULE__.Controls, & &1) == [:handoff, :decision]

    {:ok, waiting} =
      Waits.start("cancel-handoff", WaitThenHandoff, %{id: 11}, ctx, now: 0)

    {:waiting, [request]} = Waits.status(waiting)
    assert {:ok, 1} = Memory.save("cancel-handoff", 0, waiting, store)
    {:ok, 1, waiting} = Memory.load("cancel-handoff", store)
    {:ok, cancelled} = Waits.cancel(waiting)
    assert {:ok, 2} = Memory.save("cancel-handoff", 1, cancelled, store)
    {:ok, 2, cancelled} = Memory.load("cancel-handoff", store)
    assert :cancelled = Waits.status(cancelled)

    assert {:error, %{details: %{reason: :cancelled}}} =
             Waits.accept(cancelled, event(request, "cancelled", 11), ctx, now: 1)

    assert Agent.get(__MODULE__.Controls, & &1) == [:handoff, :decision]
    Memory.close(store)
  end

  test "a later wait preserves an earlier branch at a mixed-depth join" do
    flow =
      Flow.new!(%{
        name: "mixed_depth",
        components: [
          %{kind: :await, name: "active", event: "go"},
          %{kind: :timer, name: "delay", after_ms: 10},
          %{kind: :await, name: "future", event: "later", needs: ["delay"]}
        ],
        output: %{active: Ref.result("active"), future: Ref.result("future")}
      })

    {:ok, workflow} = Waits.start("mixed-depth", flow, %{}, %{}, now: 0)
    {:waiting, requests} = Waits.status(workflow)
    active = Enum.find(requests, &(&1.path == ["active"]))

    {:ok, workflow} =
      Waits.accept(
        workflow,
        %{id: "early", path: ["future"], event: "later", payload: %{later: true}},
        %{},
        now: 1
      )

    {:ok, workflow} =
      Waits.accept(
        workflow,
        %{id: "active", wait_id: active.id, event: "go", payload: %{now: true}},
        %{},
        now: 2
      )

    {:ok, workflow} = Waits.advance(workflow, %{}, now: 10)

    assert {:complete, {:ok, %{active: %{now: true}, future: %{later: true}}}} =
             Waits.status(workflow)
  end

  for recovery <- [:snapshot, :events],
      order <- [:short_first, :long_first],
      delivery <- [:early, :active] do
    @tag recovery: recovery, order: order, delivery: delivery
    test "mixed-depth join after #{recovery} with #{order} and #{delivery} input", %{
      context: ctx,
      recovery: recovery,
      order: order,
      delivery: delivery
    } do
      flow =
        Flow.new!(%{
          name: "mixed_depth_effects",
          components: [
            %{kind: :await, name: "active", event: "approved"},
            %{kind: :step, name: "short", action: Record, params: %{id: 1}, needs: ["active"]},
            %{kind: :timer, name: "delay", after_ms: 10},
            %{kind: :await, name: "future", event: "approved", needs: ["delay"]},
            %{kind: :step, name: "long", action: Record, params: %{id: 2}, needs: ["future"]}
          ],
          output: %{short: Ref.result("short"), long: Ref.result("long")}
        })

      {:ok, workflow} = Waits.start("mixed-depth-effects", flow, %{}, ctx, now: 0)
      {:waiting, requests} = Waits.status(workflow)
      active = Enum.find(requests, &(&1.path == ["active"]))

      workflow =
        if delivery == :early do
          {:ok, workflow} =
            Waits.accept(
              recover(workflow, recovery),
              %{id: "early", path: ["future"], event: "approved", payload: %{id: 2}},
              ctx,
              now: 1
            )

          workflow
        else
          workflow
        end

      finish_long = fn workflow ->
        {:ok, workflow} = Waits.advance(recover(workflow, recovery), ctx, now: 10)

        if delivery == :active do
          {:waiting, requests} = Waits.status(workflow)
          future = Enum.find(requests, &(&1.path == ["future"]))
          assert future

          {:ok, workflow} =
            Waits.accept(recover(workflow, recovery), event(future, "future", 2), ctx, now: 11)

          workflow
        else
          workflow
        end
      end

      input = event(active, "active", 1)

      completed =
        case order do
          :short_first ->
            {:ok, workflow} = Waits.accept(recover(workflow, recovery), input, ctx, now: 2)
            assert {:waiting, [%{path: ["delay"]}]} = Waits.status(workflow)
            assert Agent.get(__MODULE__.Counter, & &1) == [1]
            finish_long.(workflow)

          :long_first ->
            workflow = finish_long.(workflow)
            assert {:waiting, [%{path: ["active"]}]} = Waits.status(workflow)
            assert Agent.get(__MODULE__.Counter, & &1) == [2]
            {:ok, completed} = Waits.accept(recover(workflow, recovery), input, ctx, now: 12)
            completed
        end

      expected =
        {:complete, {:ok, %{short: %{id: 1}, long: %{id: 2}}, [%{recorded: 1}, %{recorded: 2}]}}

      assert Waits.status(completed) == expected
      completed = recover(completed, recovery)
      assert Waits.status(completed) == expected
      refute Runic.Workflow.is_runnable?(completed)
      assert {:ok, ^completed} = Waits.accept(completed, input, ctx, now: 13)
      assert Enum.sort(Agent.get(__MODULE__.Counter, & &1)) == [1, 2]
    end
  end

  test "nested waits retain separate paths, partial results, and completed effects", %{
    context: ctx
  } do
    {:ok, workflow} = Waits.start("nested", nested(), %{}, ctx, now: 0)
    assert {:waiting, [left, right]} = Waits.status(workflow)
    assert left.path == ["left", "approval"]
    assert right.path == ["right", "approval"]
    refute left.id == right.id
    assert Enum.sort(Agent.get(__MODULE__.Counter, & &1)) == [1, 2]
    assert {:ok, partial} = Waits.accept(restore(workflow), event(right, "right", 2), ctx, now: 1)
    assert {:waiting, [%{id: id}]} = Waits.status(partial)
    assert id == left.id
    assert {:ok, completed} = Waits.accept(restore(partial), event(left, "left", 1), ctx, now: 2)

    assert {:complete, {:ok, %{left: %{id: 1}, right: %{id: 2}}, [%{recorded: 1}, %{recorded: 2}]}} =
             Waits.status(completed)

    assert Agent.get(__MODULE__.Counter, &length/1) == 2
    assert Waits.status(restore(completed)) == Waits.status(completed)
  end

  test "parent cancellation closes every descendant after restore", %{context: ctx} do
    {:ok, workflow} = Waits.start("cancel-parent", nested(), %{}, ctx, now: 0)
    {:waiting, requests} = Waits.status(workflow)
    assert {:ok, cancelled} = Waits.cancel(restore(workflow))
    assert :cancelled = Waits.status(restore(cancelled))

    for request <- requests do
      assert {:error, %{details: %{reason: :cancelled}}} =
               Waits.accept(cancelled, event(request, request.id, 1), ctx, now: 1)
    end

    assert Agent.get(__MODULE__.Counter, &length/1) == 2
  end

  test "a nested timer keeps its activation deadline across restore", %{context: ctx} do
    parent =
      Flow.new!(%{
        name: "nested_timer",
        components: [
          %{kind: :subflow, name: "child", flow: TimerChild, params: %{id: 5}}
        ],
        output: Ref.result("child")
      })

    {:ok, workflow} = Waits.start("nested-timer", parent, %{}, ctx, now: 100)
    assert {:waiting, [%{path: ["child", "delay"], deadline: 110}]} = Waits.status(workflow)
    assert {:ok, waiting} = Waits.advance(restore(workflow), ctx, now: 109)
    assert {:waiting, [%{deadline: 110}]} = Waits.status(waiting)
    assert {:ok, completed} = Waits.advance(restore(waiting), ctx, now: 110)
    assert {:complete, {:ok, %{fired_at: 110}, [%{recorded: 5}]}} = Waits.status(completed)
    assert Agent.get(__MODULE__.Counter, & &1) == [5]
  end

  test "an Invoke-selected timer resumes without repeating its completed child", %{context: ctx} do
    {:ok, workflow} = Waits.start("invoke-timer", InvokeFlow, %{id: -1}, ctx, now: 100)
    assert {:waiting, [%{path: ["next", "delay"], deadline: 110}]} = Waits.status(workflow)
    assert {:ok, completed} = Waits.advance(restore(workflow), ctx, now: 110)
    assert {:complete, {:ok, %{fired_at: 110}, [%{recorded: -1}]}} = Waits.status(completed)
    assert Agent.get(__MODULE__.Counter, & &1) == [-1]
    assert Agent.get(__MODULE__.Controls, & &1) == [:expand, :decision]
  end

  test "Invoke-selected wait identity includes its parent path", %{context: ctx} do
    {:ok, workflow} = Waits.start("invoke", InvokeFlow, %{id: 7}, ctx, now: 0)
    assert {:waiting, [request]} = Waits.status(workflow)
    assert request.path == ["next", "approval"]

    assert {:ok, completed} =
             Waits.accept(restore(workflow), event(request, "selected", 7), ctx, now: 1)

    assert {:complete, {:ok, %{id: 7}, [%{recorded: 7}]}} = Waits.status(completed)
    assert Agent.get(__MODULE__.Counter, & &1) == [7]
    assert Agent.get(__MODULE__.Controls, & &1) == [:expand, :decision]
  end

  test "a nested Invoke keeps the complete path during event-log recovery", %{context: ctx} do
    parent =
      Flow.new!(%{
        name: "outer_invoke",
        components: [
          %{kind: :subflow, name: "outer", flow: InvokeFlow, params: %{id: 3}}
        ],
        output: Ref.result("outer")
      })

    {:ok, workflow} = Waits.start("nested-invoke", parent, %{}, ctx, now: 0)
    assert {:waiting, [request]} = Waits.status(workflow)
    assert request.path == ["outer", "next", "approval"]
    replayed = workflow |> Runic.Workflow.event_log() |> Runic.Workflow.from_events()
    assert Waits.status(replayed) == Waits.status(workflow)

    assert {:ok, completed} =
             Waits.accept(replayed, event(request, "nested-selected", 3), ctx, now: 1)

    assert {:complete, {:ok, %{id: 3}, [%{recorded: 3}]}} = Waits.status(completed)
    assert Agent.get(__MODULE__.Counter, & &1) == [3]
    assert Agent.get(__MODULE__.Controls, & &1) == [:expand, :decision]
  end

  test "prior execution input cannot release an equal-shaped nested occurrence", %{context: ctx} do
    {:ok, old} = Waits.start("old-occurrence", nested(), %{}, ctx, now: 0)
    {:ok, current} = Waits.start("new-occurrence", nested(), %{}, ctx, now: 0)
    {:waiting, [old_request | _]} = Waits.status(old)
    {:waiting, [current_request | _]} = Waits.status(current)
    refute old_request.id == current_request.id

    assert {:error, %{details: %{reason: :stale_target}}} =
             Waits.accept(restore(current), event(old_request, "stale", 1), ctx, now: 1)

    assert {:waiting, [_, _]} = Waits.status(current)
  end

  test "parallel independent waits resolve in either order with canonical effects", %{
    context: ctx
  } do
    results =
      for order <- [["left", "right"], ["right", "left"]] do
        {:ok, initial} = Waits.start("parallel-#{hd(order)}", nested(), %{}, ctx, now: 0)
        {:waiting, requests} = Waits.status(initial)

        completed =
          Enum.reduce(Enum.with_index(order, 1), initial, fn {name, now}, workflow ->
            request = Enum.find(requests, &(hd(&1.path) == name))
            id = if name == "left", do: 1, else: 2
            {:ok, next} = Waits.accept(restore(workflow), event(request, name, id), ctx, now: now)
            next
          end)

        Waits.status(completed)
      end

    assert [result, result] = results
    assert {:complete, {:ok, _, [%{recorded: 1}, %{recorded: 2}]}} = result
  end

  test "Map rejects waiting Flow bodies before even an independent Action runs", %{context: ctx} do
    component = %{
      kind: :map,
      name: "collection",
      collection: [1, 2],
      action: Child,
      params: %{id: Ref.item()}
    }

    assert_unsupported(component, ctx)
  end

  test "Iterate rejects waiting Flow bodies before external work starts", %{context: ctx} do
    component = %{
      kind: :iterate,
      name: "collection",
      action: Child,
      params: %{id: Ref.iteration_index()},
      state: %{initial: %{}, update: %{}},
      completion: true,
      max_iterations: 2
    }

    assert_unsupported(component, ctx)
  end

  test "Invoke wait recovery is equivalent for DSL, maps, and Codec", %{context: ctx} do
    definition =
      Flow.new!(%{
        name: "invoke_wait",
        components: [
          %{
            kind: :invoke,
            name: "next",
            decision: Decide,
            expander: Expand,
            params: %{id: Ref.input(:id)}
          }
        ],
        output: Ref.result("next")
      })

    assert definition == InvokeFlow.flow()

    registry =
      Jido.Codec.Registry.new!(%{
        {"map", 1} => {:schema, Jido.Joi.map()},
        {"decide", 1} => {:action, Decide},
        {"expand", 1} => {:action, Expand},
        {"id", 1} => {:atom, :id}
      })

    assert {:ok, document} = JidoActionTest.FlowCodec.encode(definition, registry)
    assert {:ok, decoded} = JidoActionTest.FlowCodec.decode(document, registry)

    results =
      for target <- [InvokeFlow, definition, decoded] do
        {:ok, workflow} = Waits.start("parity", target, %{id: 4}, ctx, now: 0)
        {:waiting, [request]} = Waits.status(workflow)
        assert request.path == ["next", "approval"]

        {:ok, completed} =
          Waits.accept(restore(workflow), event(request, "parity", 4), ctx, now: 1)

        Waits.status(completed)
      end

    assert length(Enum.uniq(results)) == 1
  end

  test "DSL rejects Map and Iterate Flow bodies at compilation" do
    for {name, declaration} <- [
          {"Map", ~s|map "collection", action: #{inspect(Child)}, collection: [1, 2], params: %{id: item()}|},
          {"Iterate",
           """
           iterate "collection" do
             action #{inspect(Child)}
             params %{id: iteration_index()}
             state Jido.Joi.map(), initial: %{}
             repeat 2
           end
           """}
        ] do
      source = """
      defmodule #{inspect(__MODULE__)}.Unsupported#{name} do
        use Jido.Flow, name: "unsupported_#{name}"
        flow do
          #{declaration}
          output result("collection")
        end
      end
      """

      assert_raise CompileError, ~r/wrong target kind/, fn -> Code.compile_string(source) end
    end

    assert Agent.get(__MODULE__.Counter, & &1) == []
  end

  defp assert_unsupported(component, context) do
    definition =
      Flow.new!(%{
        name: "unsupported",
        components: [
          %{kind: :step, name: "external", action: Record, params: %{id: 9}},
          component
        ],
        output: Ref.result("collection")
      })

    registry =
      Jido.Codec.Registry.new!(%{
        {"map", 1} => {:schema, Jido.Joi.map()},
        {"child", 1} => {:action, Child},
        {"record", 1} => {:action, Record},
        {"id", 1} => {:atom, :id}
      })

    assert {:ok, encoded} = JidoActionTest.FlowCodec.encode(definition, registry)
    assert {:ok, decoded} = JidoActionTest.FlowCodec.decode(encoded, registry)

    for target <- [definition, decoded] do
      assert {:error, %{details: %{expected: :action, actual: :flow}}} =
               Waits.start("unsupported", target, %{}, context, now: 0)

      assert {:error, %{details: %{expected: :action, actual: :flow}}} = Jido.Exec.compile(target)
    end

    assert Agent.get(__MODULE__.Counter, & &1) == []
  end

  defp nested do
    Flow.new!(%{
      name: "nested_waits",
      components: [
        %{kind: :subflow, name: "left", flow: Child, params: %{id: 1}},
        %{kind: :subflow, name: "right", flow: Child, params: %{id: 2}}
      ],
      output: %{left: Ref.result("left"), right: Ref.result("right")}
    })
  end

  defp event(request, id, value),
    do: %{id: id, wait_id: request.id, event: "approved", payload: %{id: value}}

  defp restore(workflow) do
    {:ok, restored} = workflow |> Runic.Runner.encode_snapshot() |> Runic.Runner.decode_snapshot()
    restored
  end

  defp recover(workflow, :snapshot), do: restore(workflow)

  defp recover(workflow, :events),
    do: workflow |> Runic.Workflow.event_log() |> Runic.Workflow.from_events()
end
