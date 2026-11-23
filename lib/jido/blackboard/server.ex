defmodule Jido.Blackboard.Server do
  @moduledoc false

  use GenServer

  alias Jido.{Blackboard, Id}

  def start_link({instance, name, initial}) when is_atom(instance) and not is_nil(instance) do
    GenServer.start_link(__MODULE__, initial, name: Blackboard.via(instance, name))
  end

  def start_link(_args), do: {:error, :jido_instance_required}

  @impl true
  def init(initial), do: {:ok, %{values: initial, generation: Id.uuid7(), version: 0}}

  @impl true
  def handle_call(:read, _from, state), do: {:reply, {:ok, snapshot(state)}, state}

  def handle_call({:patch, expected, put, delete}, _from, state) do
    if expected == revision(state) do
      values = state.values |> Map.drop(delete) |> Map.merge(put)
      next = %{state | values: values, version: state.version + 1}
      {:reply, {:ok, snapshot(next)}, next}
    else
      {:reply, {:error, :conflict}, state}
    end
  end

  defp snapshot(state), do: %{values: state.values, revision: revision(state)}
  defp revision(state), do: state.generation <> ":" <> Integer.to_string(state.version)
end
