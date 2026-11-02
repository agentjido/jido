defmodule Jido.Exec.Runner.DurabilityTest do
  use Covenant.Case, component: "jido_action.execution", async: false
  @moduletag obligation: "jido_action.execution.I22"

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref

  defmodule CheckpointGate do
    use GenServer

    def start_link(owner), do: GenServer.start_link(__MODULE__, owner, name: __MODULE__)
    def wait(label), do: GenServer.call(__MODULE__, {:wait, label}, :infinity)
    def open, do: GenServer.call(__MODULE__, :open)

    @impl GenServer
    def init(owner), do: {:ok, %{owner: owner, open?: false, waiting: []}}

    @impl GenServer
    def handle_call({:wait, label}, from, %{open?: false} = state) do
      send(state.owner, {:checkpoint_waiting, label})
      {:noreply, %{state | waiting: [from | state.waiting]}}
    end

    def handle_call({:wait, _label}, _from, %{open?: true} = state),
      do: {:reply, :ok, state}

    def handle_call(:open, _from, state) do
      Enum.each(state.waiting, &GenServer.reply(&1, :ok))
      {:reply, :ok, %{state | open?: true, waiting: []}}
    end
  end

  defmodule Recorder do
    use GenServer

    def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
    def completed(step), do: GenServer.call(__MODULE__, {:completed, step})
    def steps, do: GenServer.call(__MODULE__, :steps)

    @impl GenServer
    def init(steps), do: {:ok, steps}

    @impl GenServer
    def handle_call({:completed, step}, _from, steps) do
      {:reply, :ok, steps ++ [step]}
    end

    def handle_call(:steps, _from, steps), do: {:reply, steps, steps}
  end

  defmodule Gate do
    use GenServer

    def start_link(test_pid), do: GenServer.start_link(__MODULE__, test_pid, name: __MODULE__)
    def wait, do: GenServer.call(__MODULE__, :wait, :infinity)
    def open, do: GenServer.call(__MODULE__, :open)

    @impl GenServer
    def init(test_pid), do: {:ok, %{open?: false, test_pid: test_pid, waiting: []}}

    @impl GenServer
    def handle_call(:wait, from, %{open?: false} = state) do
      send(state.test_pid, :step_6_waiting)
      {:noreply, %{state | waiting: [from | state.waiting]}}
    end

    def handle_call(:wait, _from, %{open?: true} = state), do: {:reply, :ok, state}

    def handle_call(:open, _from, state) do
      Enum.each(state.waiting, &GenServer.reply(&1, :ok))
      {:reply, :ok, %{state | open?: true, waiting: []}}
    end
  end

  defmodule DurableStep do
    use Jido.Action,
      name: "durable_step",
      schema: Jido.Joi.object(%{step: Jido.Joi.integer(), value: Jido.Joi.integer()}),
      output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

    @impl true
    def run(%{step: 6, value: value}, _context) do
      :ok = Gate.wait()
      :ok = Recorder.completed(6)
      {:ok, %{value: value + 1}}
    end

    def run(%{step: step, value: value}, _context) do
      :ok = Recorder.completed(step)
      {:ok, %{value: value + 1}}
    end
  end

  defmodule DurableMapItem do
    use Jido.Action, name: "durable_map_item"

    @impl true
    def run(%{index: 1} = params, _context) do
      :ok = CheckpointGate.wait({:map, 1})
      complete(params)
    end

    def run(params, _context), do: complete(params)

    defp complete(%{index: index, value: value}) do
      :ok = Recorder.completed({:map, index})
      {:ok, %{index: index, value: value * 2}}
    end
  end

  defmodule DurableIteration do
    use Jido.Action, name: "durable_iteration"

    @impl true
    def run(%{index: 1} = params, _context) do
      :ok = CheckpointGate.wait({:iterate, 1})
      complete(params)
    end

    def run(params, _context), do: complete(params)

    defp complete(%{index: index, count: count}) do
      :ok = Recorder.completed({:iterate, index})
      {:ok, %{count: count + 1}}
    end
  end

  defmodule DurableNestedStep do
    use Jido.Action, name: "durable_nested_step"

    @impl true
    def run(%{step: 2} = params, _context) do
      :ok = CheckpointGate.wait({:nested, 2})
      complete(params)
    end

    def run(params, _context), do: complete(params)

    defp complete(%{step: step, value: value}) do
      :ok = Recorder.completed({:nested, step})
      {:ok, %{value: value + 1}}
    end
  end

  defmodule DurableChildFlow do
    use Jido.Flow, name: "durable_child"

    flow do
      step "first",
        action: DurableNestedStep,
        params: %{step: 1, value: input(:value)}

      step "second",
        action: DurableNestedStep,
        params: %{step: 2, value: result("first", :value)}

      output result("second")
    end
  end

  defmodule InvokeDecision do
    use Jido.Action, name: "durable_invoke_decision"

    @impl true
    def run(params, _context) do
      :ok = Recorder.completed(:invoke_decision)
      {:ok, params}
    end
  end

  defmodule InvokeExpand do
    use Jido.Action, name: "durable_invoke_expand"

    @impl true
    def run(%{value: value, target: target}, _context) do
      :ok = Recorder.completed(:invoke_expander)
      {:continue, %{value: value}, target}
    end
  end

  defmodule InvokeTargetStep do
    use Jido.Action, name: "durable_invoke_target_step"

    @impl true
    def run(%{value: value}, _context) do
      :ok = CheckpointGate.wait(:invoke_target)
      :ok = Recorder.completed(:invoke_target)
      {:ok, %{value: value + 1}}
    end
  end

  defmodule InvokeTargetFlow do
    use Jido.Flow, name: "durable_invoke_target_flow"

    flow do
      step "target",
        action: InvokeTargetStep,
        params: %{value: input(:value)}

      output result("target")
    end
  end

  defmodule HandoffDecision do
    use Jido.Action, name: "durable_handoff_decision"

    @impl true
    def run(%{value: value}, _context), do: {:ok, %{value: value}, [:handoff_effect]}
  end

  defmodule HandoffSelector do
    use Jido.Action, name: "durable_handoff_selector"

    @impl true
    def run(params, _context),
      do: {:handoff, params, Jido.Exec.Runner.DurabilityTest.HandoffTarget}
  end

  defmodule HandoffTarget do
    use Jido.Action,
      name: "durable_handoff_target",
      schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

    @impl true
    def run(_params, _context), do: raise("successor must run in a new execution")
  end

  test "Runic restores a ten-step Flow at the sixth Action" do
    start_supervised!(Recorder)
    start_supervised!({Gate, self()})
    start_supervised!({Runic.Runner, name: __MODULE__.Runner})

    flow = ten_step_flow()
    execution_id = {:durable, System.unique_integer([:positive])}
    test_pid = self()

    dispatch_hook = fn runnable, _state ->
      if runnable.node.name == "step_6" do
        send(test_pid, {:step_6_identity, runnable.activation_id, runnable.attempt_id})
      end
    end

    assert {:ok, _worker} =
             Exec.start(
               __MODULE__.Runner,
               execution_id,
               flow,
               %{value: 0},
               %{},
               max_concurrency: 1,
               checkpoint_strategy: :every_cycle,
               hooks: [on_dispatch: dispatch_hook]
             )

    assert_receive :step_6_waiting
    assert_receive {:step_6_identity, activation_id, attempt_id}
    assert Recorder.steps() == Enum.to_list(1..5)

    assert :ok = Runic.Runner.checkpoint(__MODULE__.Runner, execution_id)
    assert :ok = Runic.Runner.stop(__MODULE__.Runner, execution_id, persist: true)

    :ok = Gate.open()

    assert {:ok, _worker} =
             Runic.Runner.resume(__MODULE__.Runner, execution_id,
               max_concurrency: 1,
               hooks: [
                 on_dispatch: dispatch_hook,
                 on_idle: fn _state -> send(test_pid, :resumed_flow_idle) end
               ]
             )

    assert_receive {:step_6_identity, ^activation_id, ^attempt_id}
    assert_receive :resumed_flow_idle, 2_000
    assert Recorder.steps() == Enum.to_list(1..10)

    assert {:ok, %{result: %{value: 10}}} =
             Runic.Runner.get_results(__MODULE__.Runner, execution_id, [])

    assert {:ok, workflow} = Runic.Runner.get_workflow(__MODULE__.Runner, execution_id)
    assert Exec.result(workflow) == {:ok, %{value: 10}}

    {store, store_state} = Runic.Runner.get_store(__MODULE__.Runner)
    assert {:ok, events} = store.stream(execution_id, store_state)

    persisted = Enum.to_list(events)
    refute Enum.any?(persisted, &match?(%Jido.Instruction{}, &1))
    refute inspect(persisted) =~ "__jido_flow__"
  end

  test "Runic restores unfinished Map items without replaying completed items" do
    start_supervised!(Recorder)
    start_supervised!({CheckpointGate, self()})
    runner = __MODULE__.MapRunner
    start_supervised!({Runic.Runner, name: runner})

    flow =
      Flow.new!(%{
        name: "durable_map",
        components: [
          %{
            kind: :map,
            name: "items",
            collection: Ref.input(:items),
            action: DurableMapItem,
            params: %{value: Ref.item(), index: Ref.item_index()}
          }
        ],
        output: %{items: Ref.result("items")}
      })

    execution_id = {:durable_map, System.unique_integer([:positive])}
    start_execution(runner, execution_id, flow, %{items: [2, 3, 4]})

    assert_receive {:checkpoint_waiting, {:map, 1}}, 2_000
    # Dispatch order is not a Map contract; result order is.
    completed_before_stop = Recorder.steps()
    assert {:map, 0} in completed_before_stop
    refute {:map, 1} in completed_before_stop

    stop_and_resume(runner, execution_id)
    :ok = CheckpointGate.open()
    assert_receive {:resumed_flow_idle, ^execution_id}, 2_000

    # Each item completes exactly once across the stop and resume.
    assert Enum.sort(Recorder.steps()) == [{:map, 0}, {:map, 1}, {:map, 2}]

    assert %{
             items: [
               %{index: 0, value: 4},
               %{index: 1, value: 6},
               %{index: 2, value: 8}
             ]
           } in results(runner, execution_id)
  end

  test "Runic restores Iterate state at the next body activation" do
    start_supervised!(Recorder)
    start_supervised!({CheckpointGate, self()})
    runner = __MODULE__.IterateRunner
    start_supervised!({Runic.Runner, name: runner})

    flow =
      Flow.new!(%{
        name: "durable_iterate",
        components: [
          %{
            kind: :iterate,
            name: "counter",
            action: DurableIteration,
            params: %{count: Ref.state(:count), index: Ref.iteration_index()},
            state: %{
              schema: Jido.Joi.object(%{count: Jido.Joi.integer()}),
              initial: %{count: 0},
              update: %{count: Ref.body_result(:count)}
            },
            completion: Jido.Expr.new!(:>=, [Ref.iteration_index(), 3]),
            max_iterations: 3
          }
        ],
        output: Ref.result("counter")
      })

    execution_id = {:durable_iterate, System.unique_integer([:positive])}
    start_execution(runner, execution_id, flow, %{})

    assert_receive {:checkpoint_waiting, {:iterate, 1}}, 2_000
    assert Recorder.steps() == [{:iterate, 0}]

    stop_and_resume(runner, execution_id)
    :ok = CheckpointGate.open()
    assert_receive {:resumed_flow_idle, ^execution_id}, 2_000

    assert Recorder.steps() == [{:iterate, 0}, {:iterate, 1}, {:iterate, 2}]

    assert Enum.any?(results(runner, execution_id), fn
             %{iterations: 3, state: %{count: 3}, output: %{count: 3}} -> true
             _value -> false
           end)
  end

  test "Runic restores progress inside a nested Flow" do
    start_supervised!(Recorder)
    start_supervised!({CheckpointGate, self()})
    runner = __MODULE__.NestedRunner
    start_supervised!({Runic.Runner, name: runner})

    flow =
      Flow.new!(%{
        name: "durable_parent",
        components: [
          %{
            kind: :subflow,
            name: "child",
            flow: DurableChildFlow,
            params: %{value: Ref.input(:value)}
          }
        ],
        output: Ref.result("child")
      })

    execution_id = {:durable_nested, System.unique_integer([:positive])}
    start_execution(runner, execution_id, flow, %{value: 0})

    assert_receive {:checkpoint_waiting, {:nested, 2}}, 2_000
    assert Recorder.steps() == [{:nested, 1}]

    stop_and_resume(runner, execution_id)
    :ok = CheckpointGate.open()
    assert_receive {:resumed_flow_idle, ^execution_id}, 2_000

    assert Recorder.steps() == [{:nested, 1}, {:nested, 2}]
    assert %{value: 2} in results(runner, execution_id)
  end

  test "Runic restores a completed Handoff value and effects" do
    runner = __MODULE__.HandoffRunner
    start_supervised!({Runic.Runner, name: runner})
    owner = self()
    id = {:durable_handoff, System.unique_integer([:positive])}

    flow =
      Flow.new!(%{
        name: "durable_handoff",
        components: [
          %{kind: :step, name: "decide", action: HandoffDecision, params: %{value: 8}},
          %{
            kind: :handoff,
            name: "next",
            selector: HandoffSelector,
            params: Ref.result("decide")
          }
        ],
        output: Ref.result("next")
      })

    options = [on_complete: fn _, _ -> send(owner, {:handoff_done, id}) end]
    assert {:ok, _worker} = Exec.start(runner, id, flow, %{}, %{}, options)
    assert_receive {:handoff_done, ^id}, 2_000

    expected =
      {:handoff, %Jido.Instruction{target: HandoffTarget, kind: :action, params: %{value: 8}}, [:handoff_effect]}

    assert Exec.result(runner, id) == expected
    assert :ok = Runic.Runner.checkpoint(runner, id)
    assert :ok = Runic.Runner.stop(runner, id, persist: true)
    assert {:ok, _worker} = Exec.resume(runner, id, %{}, options)
    assert Exec.result(runner, id) == expected
  end

  for {kind, target} <- [action: InvokeTargetStep, flow: InvokeTargetFlow] do
    test "Runic restores an Invoke #{kind} target without replaying its routing Actions" do
      start_supervised!(Recorder)
      start_supervised!({CheckpointGate, self()})
      runner = __MODULE__.InvokeRunner
      start_supervised!({Runic.Runner, name: runner})

      flow =
        Flow.new!(%{
          name: "durable_invoke",
          components: [
            %{
              kind: :invoke,
              name: "route",
              decision: InvokeDecision,
              expander: InvokeExpand,
              params: %{
                value: Ref.input(:value),
                target: unquote(target)
              }
            }
          ],
          output: Ref.result("route")
        })

      execution_id = {:durable_invoke, System.unique_integer([:positive])}
      start_execution(runner, execution_id, flow, %{value: 4})

      assert_receive {:checkpoint_waiting, :invoke_target}, 2_000
      assert Recorder.steps() == [:invoke_decision, :invoke_expander]

      assert :ok = Runic.Runner.checkpoint(runner, execution_id)

      if unquote(kind) == :flow do
        assert_dynamic_components_persisted(runner, execution_id)
      else
        assert {:ok, workflow} = Runic.Runner.get_workflow(runner, execution_id)
        assert Enum.any?(Multigraph.vertices(workflow.graph), &is_struct(&1, Runic.Workflow.Call))
      end

      assert :ok = Runic.Runner.stop(runner, execution_id, persist: true)

      resume_execution(runner, execution_id)
      :ok = CheckpointGate.open()
      assert_receive {:resumed_flow_idle, ^execution_id}, 2_000

      assert Recorder.steps() == [:invoke_decision, :invoke_expander, :invoke_target]
      assert %{value: 5} in results(runner, execution_id)
    end
  end

  test "an accepted Invoke Action is not repeated after a manual checkpoint" do
    start_supervised!(Recorder)
    start_supervised!({CheckpointGate, self()})
    :ok = CheckpointGate.open()
    runner = __MODULE__.AcceptedInvokeRunner
    start_supervised!({Runic.Runner, name: runner})
    flow = invoke_action_flow()
    id = {:accepted_invoke, System.unique_integer([:positive])}
    owner = self()
    tag = make_ref()
    hooks = [on_complete: fn _runnable, _duration, _state -> send(owner, {tag, :accepted}) end]

    assert {:ok, _worker} =
             Exec.start(runner, id, flow, %{value: 4}, %{},
               dispatch_mode: :manual,
               hooks: hooks
             )

    Enum.reduce_while(1..10, nil, fn _, _ ->
      assert {:ok, _workflow} = Exec.step(runner, id)
      assert_receive {^tag, :accepted}, 1_000
      if :invoke_target in Recorder.steps(), do: {:halt, nil}, else: {:cont, nil}
    end)

    assert Recorder.steps() == [:invoke_decision, :invoke_expander, :invoke_target]
    assert {:error, _incomplete} = Exec.result(runner, id)
    assert :ok = Runic.Runner.checkpoint(runner, id)

    assert {:ok, %{status: :saved, pending_events: 0}} =
             Runic.Runner.persistence_status(runner, id)

    assert :ok = Runic.Runner.stop(runner, id, persist: true)

    assert {:ok, _worker} =
             Exec.resume(runner, id, %{}, dispatch_mode: :manual, hooks: hooks)

    Enum.reduce_while(1..10, nil, fn _, _ ->
      case Exec.step(runner, id) do
        {:ok, _workflow} ->
          assert_receive {^tag, :accepted}, 1_000
          {:cont, nil}

        {:complete, _workflow} ->
          {:halt, nil}
      end
    end)

    assert Exec.result(runner, id) == {:ok, %{value: 5}}
    assert Recorder.steps() == [:invoke_decision, :invoke_expander, :invoke_target]
  end

  test "managed resume rejects changed Action code" do
    target = Module.concat(__MODULE__, "Reloaded#{System.unique_integer([:positive])}")
    compile_reload_action(target, 1)

    on_exit(fn ->
      :code.purge(target)
      :code.delete(target)
    end)

    runner = __MODULE__.ReloadedTargetRunner
    start_supervised!({Runic.Runner, name: runner})

    flow =
      Flow.new!(%{
        name: "durable_changed_target",
        components: [%{kind: :step, name: "work", action: target}],
        output: Ref.result("work")
      })

    execution_id = {:changed_target, System.unique_integer([:positive])}

    assert {:ok, _worker} =
             Exec.start(runner, execution_id, flow, %{}, %{},
               dispatch_mode: :manual,
               checkpoint_strategy: :every_cycle
             )

    assert :ok = Runic.Runner.checkpoint(runner, execution_id)
    assert :ok = Runic.Runner.stop(runner, execution_id, persist: true)

    :code.purge(target)
    :code.delete(target)
    compile_reload_action(target, 2)

    owner = self()

    assert {:ok, _worker} =
             Exec.resume(runner, execution_id, %{},
               hooks: [
                 on_idle: fn _state -> send(owner, {:changed_target_idle, execution_id}) end
               ]
             )

    assert_receive {:changed_target_idle, ^execution_id}, 2_000

    assert {:error, %Jido.Action.Error.ConfigurationError{details: details}} =
             Exec.result(runner, execution_id)

    assert details.reason == :incompatible_target
    assert details.node == "work"
    assert details.node_path == ["work"]
  end

  @tag obligation: "jido_action.execution.I20"
  test "cancellation stops a selected Invoke Action" do
    start_supervised!(Recorder)
    start_supervised!({CheckpointGate, self()})
    runner = __MODULE__.CancelledInvokeRunner
    start_supervised!({Runic.Runner, name: runner})
    id = {:cancelled_invoke, System.unique_integer([:positive])}
    assert {:ok, worker} = Exec.start(runner, id, invoke_action_flow(), %{value: 4})
    assert_receive {:checkpoint_waiting, :invoke_target}, 2_000
    [{task, _reply_tag}] = :sys.get_state(CheckpointGate).waiting
    task_monitor = Process.monitor(task)
    worker_monitor = Process.monitor(worker)
    assert :ok = Runic.Runner.cancel(runner, id)
    assert_receive {:DOWN, ^task_monitor, :process, ^task, _reason}, 2_000
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _reason}, 2_000
    assert Recorder.steps() == [:invoke_decision, :invoke_expander]
    assert {:error, :not_found} = Exec.result(runner, id)
  end

  defp invoke_action_flow do
    Flow.new!(%{
      name: "durable_action_invoke",
      components: [
        %{
          kind: :invoke,
          name: "route",
          decision: InvokeDecision,
          expander: InvokeExpand,
          params: %{value: Ref.input(:value), target: InvokeTargetStep}
        }
      ],
      output: Ref.result("route")
    })
  end

  defp ten_step_flow do
    components =
      Enum.map(1..10, fn step ->
        value = if step == 1, do: Ref.input(:value), else: Ref.result("step_#{step - 1}", :value)

        %{
          kind: :step,
          name: "step_#{step}",
          action: DurableStep,
          params: %{step: step, value: value}
        }
      end)

    Flow.new!(%{
      name: "durable_ten_steps",
      components: components,
      output: Ref.result("step_10")
    })
  end

  defp start_execution(runner, execution_id, flow, input) do
    assert {:ok, _worker} =
             Exec.start(runner, execution_id, flow, input, %{},
               max_concurrency: 1,
               checkpoint_strategy: :every_cycle
             )
  end

  defp stop_and_resume(runner, execution_id) do
    assert :ok = Runic.Runner.checkpoint(runner, execution_id)
    assert :ok = Runic.Runner.stop(runner, execution_id, persist: true)
    resume_execution(runner, execution_id)
  end

  defp resume_execution(runner, execution_id) do
    test_pid = self()

    assert {:ok, _worker} =
             Runic.Runner.resume(runner, execution_id,
               max_concurrency: 1,
               hooks: [
                 on_idle: fn _state -> send(test_pid, {:resumed_flow_idle, execution_id}) end
               ]
             )
  end

  defp results(runner, execution_id) do
    assert {:ok, productions} = Runic.Runner.get_results(runner, execution_id)
    productions
  end

  defp assert_dynamic_components_persisted(runner, execution_id) do
    {store, store_state} = Runic.Runner.get_store(runner)
    assert {:ok, events} = store.stream(execution_id, store_state)

    assert Enum.any?(events, fn
             %Runic.Workflow.ComponentAdded{name: name, workflow_definition: definition}
             when is_binary(name) and not is_nil(definition) ->
               String.starts_with?(name, "__jido_invoke__/")

             _event ->
               false
           end)
  end

  defp compile_reload_action(target, version) do
    Code.compile_string("""
    defmodule #{inspect(target)} do
      use Jido.Action, name: "durable_reloaded_action"

      @impl true
      def run(_params, _context), do: {:ok, %{version: #{version}}}
    end
    """)
  end
end
