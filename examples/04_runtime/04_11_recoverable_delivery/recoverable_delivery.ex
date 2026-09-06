defmodule Jido.Examples.RecoverableDelivery.Deliver do
  @moduledoc false
  @schema Zoi.struct(__MODULE__, %{effect_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.RecoverableDelivery.Confirm do
  @moduledoc false
  @schema Zoi.struct(__MODULE__, %{effect_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.RecoverableDelivery.Output do
  @moduledoc """
  An explicit delivery Plugin with pending and completed work in Agent state.

  The effect ID belongs to the application. Reusing an ID with another value
  rejects the whole candidate. Completion is a new Turn, with a new revision.
  Completed IDs remain in this small example so a later command cannot reuse
  one. A production policy must set a retention period for these records.
  """
  use Jido.Plugin
  alias Jido.Examples.RecoverableDelivery.{Confirm, Deliver, Worker}

  @impl true
  def state_spec(_opts) do
    entries = Zoi.map(Zoi.string() |> Zoi.min(1), Zoi.integer())

    {:delivery,
     Zoi.object(%{pending: entries, completed: entries})
     |> Zoi.default(%{pending: %{}, completed: %{}})}
  end

  @impl true
  def directives(_opts), do: [Deliver, Confirm]

  @impl true
  def validate_directive(%module{} = directive, _opts), do: Zoi.parse(module.schema(), directive)

  @impl true
  def update_state(state, directives, _opts) do
    Enum.reduce_while(directives, {:ok, state}, fn directive, {:ok, current} ->
      case apply_intent(current, directive) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  @impl true
  def dispatch(runtime, %Deliver{}, _context, _opts), do: GenServer.cast(runtime, :wake)
  def dispatch(_runtime, %Confirm{}, _context, _opts), do: :ok

  def child_spec(init), do: Supervisor.child_spec({Worker, init}, id: __MODULE__)

  defp apply_intent(state, %Deliver{effect_id: id, value: value}) do
    case Map.fetch(Map.merge(state.pending, state.completed), id) do
      :error -> {:ok, %{state | pending: Map.put(state.pending, id, value)}}
      {:ok, ^value} -> {:ok, state}
      {:ok, _other} -> {:error, :effect_identity_conflict}
    end
  end

  defp apply_intent(state, %Confirm{effect_id: id, value: value}) do
    cond do
      Map.get(state.completed, id) == value ->
        {:ok, state}

      Map.get(state.pending, id) == value ->
        {:ok,
         %{
           state
           | pending: Map.delete(state.pending, id),
             completed: Map.put(state.completed, id, value)
         }}

      true ->
        {:error, :unknown_delivery_confirmation}
    end
  end
end

defmodule Jido.Examples.RecoverableDelivery do
  @moduledoc """
  REC-01: commit a value and explicit delivery intent in the same checkpoint.

  A supervised Plugin resumes pending work after restore. A later Signal
  records completion. Delivery can repeat, so the sink checks stable effect
  IDs. Ordinary Directives have no automatic replay guarantee.
  """
  use Jido.Agent, name: "example_recoverable_delivery"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
    plugin __MODULE__.Output
  end

  routes do
    signal_source "/examples/recovery"

    route "recovery.record_and_deliver" do
      action %{effect_id: effect_id, value: value},
        name: "example_recoverable_delivery",
        schema: Zoi.object(%{effect_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()}),
        context: context do
        effect = %Jido.Examples.RecoverableDelivery.Deliver{effect_id: effect_id, value: value}
        {:ok, %{context.agent_state | value: value}, [effect]}
      end

      define :record_and_deliver, args: [:effect_id, :value]
    end

    route "recovery.delivery_confirmed" do
      action %{effect_id: effect_id, value: value},
        name: "example_confirm_delivery",
        schema: Zoi.object(%{effect_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()}),
        context: context do
        confirmation = %Jido.Examples.RecoverableDelivery.Confirm{
          effect_id: effect_id,
          value: value
        }

        {:ok, context.agent_state, [confirmation]}
      end

      define :confirm_delivery, args: [:effect_id, :value]
    end
  end
end

defmodule Jido.Examples.RecoverableDelivery.Sink do
  @moduledoc """
  An external recording sink with idempotent writes and an optional test barrier.

  It lives outside the Agent and its checkpoint. The test observer sees each
  delivery attempt. Barriers hold the real worker task before the sink write
  or before its reply. They do not replace SDK dispatch or commit.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: address(Keyword.fetch!(opts, :jido)))
  end

  def records(jido), do: GenServer.call(address(jido), :records)

  def hold(jido, stage) when stage in [:none, :before_write, :after_write],
    do: GenServer.call(address(jido), {:hold, stage})

  def available(jido, value), do: GenServer.call(address(jido), {:available, value})

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
       observer: Keyword.get(opts, :observer),
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
    if state.observer, do: send(state.observer, {:effect_attempt, effect_id, worker})
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
    end
  end

  defp barrier(_stage, _expected), do: :ok
end
