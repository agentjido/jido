defmodule Jido.Examples.RecoverableDelivery.Deliver do
  @moduledoc "Portable intent to deliver one value under a stable effect ID."

  @schema Zoi.struct(__MODULE__, %{
            effect_id: Zoi.string() |> Zoi.min(1),
            value: Zoi.integer()
          })

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end

defmodule Jido.Examples.RecoverableDelivery.Confirm do
  @moduledoc "Portable intent to acknowledge one completed delivery."

  @schema Zoi.struct(__MODULE__, %{
            effect_id: Zoi.string() |> Zoi.min(1),
            value: Zoi.integer()
          })

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end

defmodule Jido.Examples.RecoverableDelivery.Output do
  @moduledoc "A delivery Plugin with pending and completed work in Agent state."

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
