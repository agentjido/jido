defmodule JidoCoreBench.Add do
  @moduledoc false
  use Jido.Action, name: "core_bench_add"
  @impl true
  def run(params, context) do
    JidoCoreBench.Fixtures.barrier(context)
    state = Map.get(params, :state, context.agent_state)
    {:ok, %{state | count: state.count + 1}}
  end
end

defmodule JidoCoreBench.Fail do
  @moduledoc false
  use Jido.Action, name: "core_bench_fail"
  @impl true
  def run(_params, context) do
    JidoCoreBench.Fixtures.barrier(context)
    {:error, Jido.Error.execution_error("benchmark failure")}
  end
end

defmodule JidoCoreBench.PreparePlugin do
  @moduledoc false
  use Jido.Plugin
  @impl true
  def prepare(command, _opts), do: {:ok, command}
end

defmodule JidoCoreBench.Fixtures do
  @moduledoc false
  alias Jido.Agent, as: CoreAgent
  alias Jido.Agent.Command.Runner
  alias JidoCoreBench.{Add, Fail, PreparePlugin}

  @schema Zoi.object(%{
            count: Zoi.integer() |> Zoi.default(0),
            payload: Zoi.any() |> Zoi.default(nil)
          })

  def barrier(%{bench_observer: observer}) when is_pid(observer) do
    ref = make_ref()
    send(observer, {:bench_barrier, self(), ref})

    receive do
      {:bench_release, ^ref} -> :ok
    after
      30_000 -> raise "benchmark barrier timed out"
    end
  end

  def barrier(_context), do: :ok

  def payload(:small), do: nil
  def payload(:large_map), do: Map.new(1..1_000, &{&1, [value: &1]})
  def payload(:large_binary), do: :binary.copy(<<42>>, 1_048_576)
  def payload(:large_list), do: Enum.to_list(1..5_000)

  def definition(count \\ 1, target \\ Add, plugins \\ []) do
    CoreAgent.new!(
      name: "core_bench",
      schema: @schema,
      plugins: plugins,
      routes: for(n <- 1..count, do: {"bench.add.#{n}", target})
    )
  end

  def agent(count \\ 1, data \\ nil, target \\ Add, plugins \\ []) do
    definition(count, target, plugins)
    |> CoreAgent.instantiate!(id: "core-bench", state: %{count: 0, payload: data})
  end

  def signal(count \\ 1), do: Jido.Signal.new!("bench.add.#{count}", %{}, source: "/bench")

  def flow do
    alias Jido.Flow.{Step, Ref}

    Jido.Flow.new!(
      name: "core_bench_flow",
      components: [
        Step.new!(name: "first", action: Add, params: %{}),
        Step.new!(name: "second", action: Add, params: %{state: Ref.result("first")})
      ],
      output: Ref.result("second")
    )
  end

  # The older Action revision uses :jido. Released v3 uses :task_supervisor.
  # This lets one fixed benchmark tool measure either committed core revision.
  def exec_opts do
    Code.ensure_loaded!(Jido.Exec)

    if function_exported?(Jido.Exec, :task_supervisor_name, 1),
      do: [jido: JidoCoreBench],
      else: [task_supervisor: JidoCoreBench.TaskSupervisor]
  end

  def checked(id, setup, run, check, retained \\ fn _prepared, result -> %{result: result} end) do
    %{id: id, setup: setup, run: run, check: check, retained: retained}
  end

  def equal!(actual, expected) do
    if actual != expected, do: raise("unexpected benchmark result: #{inspect(actual, limit: 5)}")
    :ok
  end

  def candidate!(result, count, data) do
    case result do
      {:ok, %CoreAgent{state: state, id: "core-bench"}, []} ->
        equal!(state, %{count: count, payload: data})

      other ->
        raise "unexpected candidate: #{inspect(other, limit: 5)}"
    end
  end

  def workloads(sizes, payloads) do
    for size <- sizes,
        kind <- payloads,
        operation <- [:new, :validate, :prepare, :route, :cmd, :flow, :transition, :checkpoint] do
      data = payload(kind)
      target = if operation == :flow, do: flow(), else: Add
      id = "agent/#{operation}/routes_#{size}/#{kind}"

      setup = fn context ->
        %{agent: agent(size, data, target), signal: signal(size), context: context}
      end

      run = fn p ->
        case operation do
          :new ->
            CoreAgent.instantiate(definition(size),
              id: "core-bench",
              state: %{count: 0, payload: data}
            )

          :validate ->
            CoreAgent.validate_instance(p.agent)

          :prepare ->
            Runner.prepare(p.agent, p.signal, Keyword.put(exec_opts(), :context, p.context))

          :route ->
            Runner.prepare_default_turn(p.signal, p.agent)

          :cmd ->
            CoreAgent.cmd(p.agent, p.signal, Keyword.put(exec_opts(), :context, p.context))

          :flow ->
            CoreAgent.cmd(p.agent, p.signal, Keyword.put(exec_opts(), :context, p.context))

          :transition ->
            CoreAgent.transition(p.agent, %{p.agent.state | count: 1})

          :checkpoint ->
            CoreAgent.checkpoint(p.agent)
        end
      end

      check = fn result ->
        case operation do
          op when op in [:cmd, :flow] ->
            candidate!(result, if(op == :flow, do: 2, else: 1), data)

          :prepare ->
            {:ok, %Runner.Prepared{} = p} = result

            equal!(
              {p.agent.state, p.turn.input, p.context.agent_state},
              {%{count: 0, payload: data}, %{}, %{count: 0, payload: data}}
            )

          :route ->
            {:ok, %Jido.Agent.Turn{executable: executable, input: %{}}} = result
            equal!(executable, target)

          :checkpoint ->
            {:ok, checkpoint} = result
            {:ok, restored} = CoreAgent.restore(CoreAgent, checkpoint)
            equal!(restored.state, %{count: 0, payload: data})

          op when op in [:new, :validate, :transition] ->
            {:ok, %CoreAgent{state: state}} = result
            equal!(state, %{count: if(op == :transition, do: 1, else: 0), payload: data})
        end
      end

      checked(id, setup, run, check, fn p, result -> %{agent: p.agent, result: result} end)
    end
  end

  def boundary_workloads do
    plugin =
      checked(
        "plugin/prepare",
        fn c -> {agent(1, nil, Add, [PreparePlugin]), signal(), c} end,
        fn {a, s, c} -> CoreAgent.cmd(a, s, Keyword.put(exec_opts(), :context, c)) end,
        &candidate!(&1, 1, nil)
      )

    failure =
      checked(
        "agent/failure/large_list",
        fn c -> {agent(1, payload(:large_list), Fail), signal(), c} end,
        fn {a, s, c} -> {a, CoreAgent.cmd(a, s, Keyword.put(exec_opts(), :context, c))} end,
        fn {a, {:error, %Jido.Error.ExecutionError{}}} ->
          equal!(a.state, %{count: 0, payload: payload(:large_list)})
        end,
        fn _, {a, error} -> %{original: a, error: error} end
      )

    budgets =
      for limit <- [nil, 2_000_000] do
        checked(
          "state/budget/#{inspect(limit)}",
          fn _ -> %{agent(1, payload(:large_list)) | max_state_size: limit} end,
          &Jido.Agent.StateBudget.check/1,
          fn {:ok, a} -> equal!(a.state, %{count: 0, payload: payload(:large_list)}) end
        )
      end

    [plugin, failure | budgets]
  end
end
