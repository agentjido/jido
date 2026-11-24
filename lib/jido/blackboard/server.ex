defmodule Jido.Blackboard.Server do
  @moduledoc false

  use GenServer

  alias Jido.{Blackboard, Id}
  alias Jido.Blackboard.Record
  alias Jido.Plugin.Init

  def start_link(%Init{jido: instance, options: opts} = init) when is_atom(instance) and not is_nil(instance) do
    name = Keyword.fetch!(opts, :name)
    initial = Keyword.get(opts, :initial, %{})

    with {:ok, record} <- configure(init, name) do
      Blackboard.with_lifecycle_lock(instance, name, fn ->
        GenServer.start_link(__MODULE__, {initial, record}, name: Blackboard.via(instance, name))
      end)
    end
  end

  def start_link(_args), do: {:error, :jido_instance_required}

  @impl true
  def init({values, record}) do
    initial = %{values: values, generation: Id.uuid7(), version: 0}

    case Record.open(record, initial) do
      {:ok, data} -> {:ok, %{record: record, generation: data.generation, data: data}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(message, _from, state) do
    case refresh(state) do
      {:ok, current} -> respond(message, current)
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  defp respond(:read, state), do: {:reply, {:ok, snapshot(state.data)}, state}

  defp respond({:patch, expected, put, delete}, %{data: current} = state) do
    if expected == revision(current) do
      values = current.values |> Map.drop(delete) |> Map.merge(put)
      next = %{current | values: values, version: current.version + 1}

      case Record.commit(state.record, current, next) do
        :ok ->
          {:reply, {:ok, snapshot(next)}, %{state | data: next}}

        {:error, reason} = error when reason in [:conflict, :indeterminate] ->
          {:reply, error, %{state | data: nil}}

        {:error, _reason} = error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :conflict}, state}
    end
  end

  defp refresh(%{data: nil, record: record, generation: generation} = state) do
    case Record.read(record) do
      {:ok, %{generation: ^generation} = data, _condition} -> {:ok, %{state | data: data}}
      _other -> {:error, :unavailable}
    end
  end

  defp refresh(state), do: {:ok, state}

  defp configure(%Init{jido: instance, agent_id: id, partition: partition, options: opts}, name) do
    case Keyword.get(opts, :persistence, false) do
      false ->
        {:ok, nil}

      :inherit ->
        with {:ok, address} <- Jido.agent_address(instance, id, partition: partition) do
          Record.configure(instance, address, name)
        end
    end
  end

  defp snapshot(state), do: %{values: state.values, revision: revision(state)}
  defp revision(state), do: state.generation <> ":" <> Integer.to_string(state.version)
end
