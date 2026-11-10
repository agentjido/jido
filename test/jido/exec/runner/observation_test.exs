defmodule Jido.Exec.Runner.ObservationTest do
  use Covenant.Case, component: "jido_action.execution", async: false
  @moduletag obligation: "jido_action.execution.I21"

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Runic.Workflow.Execution

  defmodule Controlled do
    use Jido.Action, name: "managed_observation"

    @impl true
    def run(params, %{observer: observer}) do
      send(Process.whereis(observer), {:started, params.label, self()})

      receive do
        :release ->
          case params.fail do
            :crash -> Process.exit(self(), {:item_crashed, params.label})
            true -> {:error, params.label}
            false -> {:ok, params, Map.get(params, :effects, [:saved])}
          end
      end
    end
  end

  defmodule CompletionScheduler do
    @behaviour Runic.Runner.Scheduler

    @impl true
    def init(opts), do: {:ok, Keyword.fetch!(opts, :observer)}

    @impl true
    defdelegate plan_dispatch(workflow, runnables, observer),
      to: Runic.Runner.Scheduler.Default

    @impl true
    def on_complete({:runnable, runnable}, _duration, observer) do
      if runnable.status == :pending, do: send(observer, :executor_ended)
      observer
    end
  end

  setup do
    runner = __MODULE__.Runner
    observer = __MODULE__.Observer
    Process.register(self(), observer)
    start_supervised!({Runic.Runner, name: runner})
    owner = self()

    hooks = [
      on_dispatch: fn _units, state -> send(owner, {:scope, state.current_execution_id}) end,
      on_failed: fn runnable, _reason, _state -> send(owner, {:failed, runnable.node.name}) end,
      on_idle: fn _state -> send(owner, :idle) end
    ]

    %{runner: runner, context: %{observer: observer}, opts: [hooks: hooks]}
  end

  test "managed results use a Runic input occurrence and reject active work", ctx do
    id = {:observed, System.unique_integer([:positive])}
    params = %{label: :one, fail: false}
    assert {:ok, _worker} = Exec.start(ctx.runner, id, Controlled, params, ctx.context, ctx.opts)
    assert_receive {:scope, scope_id}
    assert_receive {:started, :one, task}

    assert {:ok, %Execution{quiescent?: false}} =
             Runic.Runner.execution(ctx.runner, id, scope_id)

    assert {:error, %Jido.Error.ExecutionError{details: details}} =
             Exec.result(ctx.runner, id)

    assert details.reason == :execution_active
    send(task, :release)
    assert_receive :idle

    assert {:ok, observation} = Runic.Runner.execution(ctx.runner, id, scope_id)
    assert observation.quiescent?
    assert observation.id.domain == :execution
    assert observation.input_id.domain == :input_command
    assert observation.input_fact_id.domain == :fact_occurrence
    assert observation.persistence.status == :saved
    assert observation.persistence.pending_events == 0
    assert Exec.result(ctx.runner, id) == {:ok, params, [:saved]}
  end

  test "later inputs keep distinct identities and do not replace the managed result", ctx do
    id = {:repeated, System.unique_integer([:positive])}
    params = %{label: :first, fail: false}
    assert {:ok, _worker} = Exec.start(ctx.runner, id, Controlled, params, ctx.context, ctx.opts)
    assert_receive {:scope, first_id}
    assert_receive {:started, :first, task}
    send(task, :release)
    assert_receive :idle
    assert {:ok, first} = Runic.Runner.execution(ctx.runner, id, first_id)

    [second, third] =
      for _repeat <- 1..2 do
        next = %{params | label: :second}
        assert {:ok, next_id} = Runic.Runner.start_execution(ctx.runner, id, next)
        assert_receive {:started, :second, task}
        assert Exec.result(ctx.runner, id) == {:ok, params, [:saved]}
        send(task, :release)
        assert_receive :idle
        assert {:ok, observation} = Runic.Runner.execution(ctx.runner, id, next_id)
        assert observation.id != first.id
        assert observation.input_fact_id != first.input_fact_id
        assert {:ok, workflow} = Runic.Runner.get_workflow(ctx.runner, id)
        assert Exec.result(workflow, observation) == {:ok, next, [:saved]}
        assert Exec.result(ctx.runner, id) == {:ok, params, [:saved]}
        observation
      end

    assert second.id != third.id
    assert second.input_fact_id != third.input_fact_id
  end

  @tag obligation: ["jido_action.execution.I18", "jido_action.execution.I21"]
  test "managed failure selection follows component order after active work drains", ctx do
    id = {:failure, System.unique_integer([:positive])}

    assert {:ok, _worker} =
             Exec.start(
               ctx.runner,
               id,
               failure_flow(),
               %{},
               ctx.context,
               ctx.opts ++ [max_concurrency: 2]
             )

    assert_receive {:started, :a, a}
    assert_receive {:started, :b, b}
    send(b, :release)
    assert_receive {:failed, "b"}

    assert {:error, %Jido.Error.ExecutionError{details: details}} =
             Exec.result(ctx.runner, id)

    assert details.reason == :execution_active
    send(a, :release)
    assert_receive :idle

    assert {:error, %Jido.Error.ExecutionError{message: "a"}} =
             Exec.result(ctx.runner, id)
  end

  @tag obligation: ["jido_action.execution.I18", "jido_action.execution.I21"]
  test "serial managed admission selects the same first failure as concurrent admission", ctx do
    id = {:serial_failure, System.unique_integer([:positive])}

    assert {:ok, _worker} =
             Exec.start(
               ctx.runner,
               id,
               failure_flow(),
               %{},
               ctx.context,
               ctx.opts ++ [max_concurrency: 1]
             )

    assert_receive {:started, :a, task}
    send(task, :release)
    assert_receive :idle
    refute_received {:started, :b, _task}

    assert {:error, %Jido.Error.ExecutionError{message: "a"}} =
             Exec.result(ctx.runner, id)
  end

  @tag obligation: ["jido_action.execution.I18", "jido_action.execution.I19"]
  test "native Map outcomes and effects keep input order after later items finish first", ctx do
    id = {:batch_order, System.unique_integer([:positive])}

    flow =
      map_flow(%{label: Ref.item(), fail: false, effects: [Ref.item()]})

    assert {:ok, _worker} =
             Exec.start(ctx.runner, id, flow, %{items: [:a, :b, :c]}, ctx.context,
               hooks: ctx.opts[:hooks],
               max_concurrency: 2
             )

    assert_receive {:started, :a, a}
    assert_receive {:started, :b, b}
    send(b, :release)
    # Admission of c confirms that b completed while a remains active.
    assert_receive {:started, :c, c}
    send(c, :release)
    send(a, :release)
    assert_receive :idle

    assert Exec.result(ctx.runner, id) ==
             {:ok,
              %{
                items:
                  for label <- [:a, :b, :c] do
                    %{label: label, fail: false, effects: [label]}
                  end
              }, [:a, :b, :c]}
  end

  @tag obligation: "jido_action.execution.I20"
  test "native Map cancellation stops active items and admits no later item", ctx do
    id = {:batch_cancel, System.unique_integer([:positive])}
    flow = map_flow(%{label: Ref.item(), fail: false})

    assert {:ok, worker} =
             Exec.start(ctx.runner, id, flow, %{items: [:a, :b, :c]}, ctx.context,
               hooks: ctx.opts[:hooks],
               max_concurrency: 2
             )

    assert_receive {:started, :a, a}
    assert_receive {:started, :b, b}
    monitors = for task <- [worker, a, b], do: {task, Process.monitor(task)}
    assert :ok = Runic.Runner.cancel(ctx.runner, id)

    for {task, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^task, _reason}
    end

    refute_received {:started, :c, _task}
  end

  @tag :capture_log
  @tag obligation: "jido_action.execution.I18"
  test "native Map failure stops admission and selects the same item at each concurrency", ctx do
    flow = map_flow(%{label: Ref.item(), fail: true})

    errors =
      for concurrency <- [1, 2] do
        id = {:batch_failure, concurrency, System.unique_integer([:positive])}

        assert {:ok, _worker} =
                 Exec.start(ctx.runner, id, flow, %{items: [:a, :b, :c]}, ctx.context,
                   hooks: ctx.opts[:hooks],
                   max_concurrency: concurrency
                 )

        assert_receive {:started, :a, a}

        if concurrency == 2 do
          assert_receive {:started, :b, b}
          send(b, :release)
          assert_receive {:failed, "__jido_map__/items/action"}
          assert {:error, %{details: %{reason: :execution_active}}} = Exec.result(ctx.runner, id)
        end

        send(a, :release)
        assert_receive :idle
        refute_received {:started, :c, _task}
        if concurrency == 1, do: refute_received({:started, :b, _task})
        assert {:error, %{message: "a", details: details}} = Exec.result(ctx.runner, id)
        assert %{node: "items", item_index: 0, item_id: item_id} = details
        item_id
      end

    assert [id, id] = errors
  end

  @tag :capture_log
  test "native Map selects the first item after a later task crash and recovery", ctx do
    flow = map_flow(%{label: Ref.item(:label), fail: Ref.item(:fail)})
    items = [%{label: :a, fail: true}, %{label: :b, fail: :crash}, %{label: :c, fail: false}]

    results =
      for concurrency <- [1, 2] do
        id = {:batch_crash, concurrency, System.unique_integer([:positive])}

        opts =
          ctx.opts ++
            [
              max_concurrency: concurrency,
              scheduler: CompletionScheduler,
              scheduler_opts: [observer: self()]
            ]

        assert {:ok, _worker} =
                 Exec.start(ctx.runner, id, flow, %{items: items}, ctx.context, opts)

        assert_receive {:started, :a, a}

        if concurrency == 2 do
          assert_receive {:started, :b, b}
          send(b, :release)
          # The scheduler callback runs in the Worker. This query is a barrier
          # after that Worker records task loss and stops admission.
          assert_receive :executor_ended

          assert {:ok, %{status: :stopped, active_units: 1}} =
                   Runic.Runner.admission_status(ctx.runner, id)

          assert {:error, %{details: %{reason: :execution_active}}} = Exec.result(ctx.runner, id)
        end

        send(a, :release)
        assert_receive :idle
        refute_received {:started, :c, _task}
        if concurrency == 1, do: refute_received({:started, :b, _task})
        live = Exec.result(ctx.runner, id)
        assert {:ok, workflow} = Runic.Runner.get_workflow(ctx.runner, id)
        snapshot = Exec.result(workflow)
        assert :ok = Runic.Runner.checkpoint(ctx.runner, id)

        assert {:ok, %{status: :saved, pending_events: 0}} =
                 Runic.Runner.persistence_status(ctx.runner, id)

        assert :ok = Runic.Runner.stop(ctx.runner, id, persist: true)

        assert {:ok, _worker} =
                 Exec.resume(ctx.runner, id, ctx.context, opts ++ [dispatch_mode: :manual])

        assert {:ok, restored} = Runic.Runner.get_workflow(ctx.runner, id)
        restored_snapshot = Exec.result(restored)

        recovered =
          if concurrency == 2 do
            assert {:error, %{details: %{reason: :execution_active}}} =
                     Exec.result(ctx.runner, id)

            assert {:ok, _workflow} = Exec.step(ctx.runner, id)
            assert_receive {:started, :b, b}
            send(b, :release)
            assert_receive :executor_ended
            assert_receive :idle
            refute_received {:started, :a, _task}
            refute_received {:started, :c, _task}
            [Exec.result(ctx.runner, id)]
          else
            []
          end

        assert :ok = Runic.Runner.cancel(ctx.runner, id)
        [live, snapshot, restored_snapshot | recovered]
      end

    item_ids =
      for result <- List.flatten(results) do
        assert {:error, %{message: "a", details: details}} = result
        assert %{node: "items", item_index: 0, item_id: item_id} = details
        assert is_binary(item_id)
        item_id
      end

    assert length(Enum.uniq(item_ids)) == 1
  end

  for order <- [[:a, :b], [:b, :a]] do
    @tag completion_order: order
    test "failure selection survives resume after completion order #{inspect(order)}", ctx do
      id = {:failure_resume, System.unique_integer([:positive])}
      opts = ctx.opts ++ [max_concurrency: 2]

      assert {:ok, _worker} =
               Exec.start(ctx.runner, id, failure_flow(), %{}, ctx.context, opts)

      assert_receive {:started, :a, a}
      assert_receive {:started, :b, b}
      tasks = %{a: a, b: b}

      for label <- ctx.completion_order do
        name = Atom.to_string(label)
        send(tasks[label], :release)
        assert_receive {:failed, ^name}
      end

      assert_receive :idle
      assert {:error, %{message: "a", details: details}} = Exec.result(ctx.runner, id)
      assert :ok = Runic.Runner.checkpoint(ctx.runner, id)
      assert :ok = Runic.Runner.stop(ctx.runner, id, persist: true)
      assert {:ok, _worker} = Exec.resume(ctx.runner, id, ctx.context, opts)

      assert {:error, %{message: "a", details: ^details}} = Exec.result(ctx.runner, id)
      assert {:ok, workflow} = Runic.Runner.get_workflow(ctx.runner, id)
      assert {:error, %{message: "a", details: ^details}} = Exec.result(workflow)
    end
  end

  test "resumed execution keeps snapshot results and rejects active recovery", ctx do
    id = {:resumed, System.unique_integer([:positive])}
    params = %{label: :restored, fail: false}
    assert {:ok, _worker} = Exec.start(ctx.runner, id, Controlled, params, ctx.context, ctx.opts)
    assert_receive {:scope, scope_id}
    assert_receive {:started, :restored, _task}
    assert :ok = Runic.Runner.checkpoint(ctx.runner, id)
    assert :ok = Runic.Runner.stop(ctx.runner, id, persist: true)

    assert {:ok, _worker} =
             Exec.resume(ctx.runner, id, ctx.context, ctx.opts ++ [dispatch_mode: :manual])

    assert Runic.Runner.execution(ctx.runner, id, scope_id) == {:error, :not_found}

    assert {:error, %Jido.Error.ExecutionError{details: details}} =
             Exec.result(ctx.runner, id)

    assert details.reason == :execution_active
    assert {:ok, _workflow} = Exec.step(ctx.runner, id)
    assert_receive {:started, :restored, task}

    assert {:error, %Jido.Error.ExecutionError{details: %{reason: :execution_active}}} =
             Exec.result(ctx.runner, id)

    send(task, :release)
    assert_receive :idle
    assert Exec.result(ctx.runner, id) == {:ok, params, [:saved]}
  end

  test "missing managed executions keep the Runner lookup error", ctx do
    assert Exec.result(ctx.runner, :missing) == {:error, :not_found}
  end

  defp failure_flow do
    Flow.new!(%{
      name: "managed_failure_order",
      components: [
        %{kind: :step, name: "a", action: Controlled, params: %{label: :a, fail: true}},
        %{kind: :step, name: "b", action: Controlled, params: %{label: :b, fail: true}}
      ],
      output: %{a: Ref.result("a"), b: Ref.result("b")}
    })
  end

  defp map_flow(params) do
    Flow.new!(%{
      name: "managed_batch",
      components: [
        %{
          kind: :map,
          name: "items",
          collection: Ref.input(:items),
          action: Controlled,
          params: params
        }
      ],
      output: %{items: Ref.result("items")}
    })
  end
end
