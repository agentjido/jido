defmodule JidoTest.Examples.Durable.StepProbe do
  @moduledoc false
  use GenServer

  alias Jido.Examples.Durable.SavedProgress
  alias JidoTest.Examples.Durable.ObservedStep

  @doc "Returns a validated test copy of SavedProgress with the barrier Action."
  def flow do
    flow = SavedProgress.flow()

    components =
      Map.new(flow.components, fn {name, component} ->
        {name, put_in(component, [:call, :target], ObservedStep)}
      end)

    Jido.Flow.validate(%{flow | components: components})
  end

  def start_link(observer), do: GenServer.start_link(__MODULE__, observer, name: __MODULE__)
  def enter(step, value), do: GenServer.call(__MODULE__, {:enter, step, value}, 10_000)
  def complete(step), do: GenServer.call(__MODULE__, {:complete, step})
  def records, do: GenServer.call(__MODULE__, :records)
  def release, do: GenServer.call(__MODULE__, :release)

  @impl true
  def init(observer), do: {:ok, %{observer: observer, started: [], completed: [], waiter: nil}}

  @impl true
  def handle_call({:enter, step, value}, from, state) do
    state = %{state | started: state.started ++ [{step, value}]}

    if step == 6 do
      if state.observer, do: send(state.observer, {:step_6_running, elem(from, 0), value})
      {:noreply, %{state | waiter: from}}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:complete, step}, _from, state) do
    {:reply, :ok, %{state | completed: state.completed ++ [step]}}
  end

  def handle_call(:records, _from, state) do
    {:reply, Map.take(state, [:started, :completed]), state}
  end

  def handle_call(:release, _from, state) do
    GenServer.reply(state.waiter, :ok)
    {:reply, :ok, %{state | waiter: nil}}
  end
end

defmodule JidoTest.Examples.Durable.ObservedStep do
  @moduledoc false
  use Jido.Action,
    name: "observed_durable_step",
    schema: Zoi.object(%{step: Zoi.integer(), value: Zoi.integer()}),
    output_schema: Zoi.object(%{value: Zoi.integer()})

  alias JidoTest.Examples.Durable.StepProbe

  @impl true
  def run(params, context) do
    :ok = StepProbe.enter(params.step, params.value)

    with {:ok, result} <-
           Jido.Exec.run(Jido.Examples.Durable.SavedProgress.Advance, params, context) do
      :ok = StepProbe.complete(params.step)
      {:ok, result}
    end
  end
end

defmodule JidoTest.Examples.Durable.ObservedAgent do
  @moduledoc false

  def new(id) do
    agent =
      Jido.Agent.instantiate!(Jido.Examples.Durable.SavedProgress.Agent.definition(), id: id)

    {:ok, agent} =
      Jido.Agent.Composition.apply(agent, agent.state, [
        Jido.Agent.Directive.route_replace(
          "examples.durable.saved_progress.run",
          JidoTest.Examples.Durable.ObservedFlow
        )
      ])

    agent
  end
end

defmodule JidoTest.Examples.Durable.ObservedFlow do
  @moduledoc false
  @behaviour Jido.Flow
  @impl true
  def flow do
    {:ok, flow} = JidoTest.Examples.Durable.StepProbe.flow()
    flow
  end

  @impl true
  defdelegate validate_params(input), to: Jido.Examples.Durable.SavedProgress
  @impl true
  defdelegate validate_output(output), to: Jido.Examples.Durable.SavedProgress
end
