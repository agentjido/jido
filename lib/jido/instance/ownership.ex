defmodule Jido.Instance.Ownership do
  @moduledoc false

  alias Jido.AgentOwnership
  alias Jido.AgentServer.Supervisor, as: ServerSupervisor
  alias Jido.AgentServer.Worker

  @timeout 5_000

  @doc false
  @spec transfer(atom(), map(), map(), AgentOwnership.t() | nil, String.t()) ::
          {:ok, AgentOwnership.t()} | {:error, term()}
  def transfer(instance, child, owner, expected, request_id) do
    lock = {{__MODULE__, instance, child.address.partition}, self()}

    case :global.trans(
           lock,
           fn -> transfer_locked(child, owner, expected, request_id) end,
           [node()],
           0
         ) do
      :aborted -> {:error, :ownership_busy}
      result -> result
    end
  end

  @doc false
  @spec get(pid()) :: {:ok, AgentOwnership.t() | nil} | {:error, term()}
  def get(server), do: Worker.ownership(server, @timeout)

  defp transfer_locked(child, owner, expected, request_id) do
    with :ok <- reject_cycle(child.activation, owner.activation),
         do: Worker.transfer_ownership(child.server, owner, expected, request_id, @timeout)
  end

  defp reject_cycle(child, child), do: {:error, :self_ownership}

  defp reject_cycle(child, owner) do
    ancestor?(owner, child, MapSet.new())
  end

  defp ancestor?(current, child, _visited) when current == child,
    do: {:error, :ownership_cycle}

  defp ancestor?(current, child, visited) do
    if MapSet.member?(visited, current) do
      {:error, :ownership_cycle}
    else
      case ServerSupervisor.live_worker(current) do
        server when is_pid(server) ->
          case Worker.ownership_context(server, @timeout) do
            {:ok, %{parent_activation: nil}} ->
              :ok

            {:ok, %{parent_activation: parent}} when is_pid(parent) ->
              ancestor?(parent, child, MapSet.put(visited, current))

            {:error, _reason} ->
              {:error, :ownership_ancestry_unavailable}
          end

        nil ->
          {:error, :ownership_ancestry_unavailable}
      end
    end
  catch
    :exit, _reason -> {:error, :ownership_ancestry_unavailable}
  end
end
