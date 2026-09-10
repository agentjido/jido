defmodule JidoTest.RecoverableDeliverySink do
  @moduledoc false

  use GenServer

  @behaviour Jido.Examples.RecoverableDelivery.Sink

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: address(Keyword.fetch!(opts, :jido)))
  end

  def records(jido), do: GenServer.call(address(jido), :records)

  def hold(jido, stage) when stage in [:none, :before_write, :after_write],
    do: GenServer.call(address(jido), {:hold, stage})

  def available(jido, value), do: GenServer.call(address(jido), {:available, value})

  @impl Jido.Examples.RecoverableDelivery.Sink
  def deliver(jido, directive) do
    {stage, available?} = GenServer.call(address(jido), {:attempt, self(), directive.effect_id})
    barrier(stage, :before_write)

    if available? do
      with :ok <- GenServer.call(address(jido), {:write, directive}) do
        barrier(stage, :after_write)
        :ok
      end
    else
      {:error, :sink_unavailable}
    end
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       records: %{},
       observer: Keyword.fetch!(opts, :observer),
       hold: :none,
       available?: true
     }}
  end

  @impl true
  def handle_call(:records, _from, state), do: {:reply, state.records, state}

  def handle_call({:hold, stage}, _from, state), do: {:reply, :ok, %{state | hold: stage}}

  def handle_call({:available, value}, _from, state),
    do: {:reply, :ok, %{state | available?: value}}

  def handle_call({:attempt, worker, effect_id}, _from, state) do
    send(state.observer, {:effect_attempt, effect_id, worker})
    {:reply, {state.hold, state.available?}, state}
  end

  def handle_call({:write, %{effect_id: id, value: value}}, _from, state) do
    case Map.fetch(state.records, id) do
      :error -> {:reply, :ok, %{state | records: Map.put(state.records, id, value)}}
      {:ok, ^value} -> {:reply, :ok, state}
      {:ok, _other} -> {:reply, {:error, :effect_identity_conflict}, state}
    end
  end

  defp address(jido), do: {:via, Registry, {Jido.registry_name(jido), {__MODULE__, :sink}}}

  defp barrier(stage, stage) when stage != :none do
    receive do
      :release -> :ok
    after
      5_000 -> raise "delivery barrier was not released"
    end
  end

  defp barrier(_stage, _expected), do: :ok
end

defmodule JidoTest.RecoverableDeliveryAgent do
  @moduledoc false

  use Jido.Agent, name: "test_recoverable_delivery"

  alias Jido.Examples.RecoverableDelivery.{Confirm, Deliver, Output}

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
    plugin Output, config: [sink: JidoTest.RecoverableDeliverySink]
  end

  routes do
    signal_source "/test/recoverable_delivery"

    route "examples.runtime.delivery.record" do
      action %{effect_id: effect_id, value: value},
        schema: Zoi.object(%{effect_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()}),
        context: context do
        directive = struct!(Deliver, effect_id: effect_id, value: value)
        {:ok, %{context.agent_state | value: value}, [directive]}
      end

      define :record_and_deliver, args: [:effect_id, :value]
    end

    route "examples.runtime.delivery.confirm" do
      action %{effect_id: effect_id, value: value},
        schema: Zoi.object(%{effect_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()}),
        context: context do
        confirmation = struct!(Confirm, effect_id: effect_id, value: value)
        {:ok, context.agent_state, [confirmation]}
      end

      define :confirm_delivery, args: [:effect_id, :value]
    end
  end
end
