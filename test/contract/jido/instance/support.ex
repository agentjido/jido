defmodule JidoTest.InstanceContractSupport do
  @moduledoc false

  def ensure_namespace_registry(_context) do
    case Process.whereis(Jido.Instance.NamespaceRegistry) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case Supervisor.restart_child(Jido.Supervisor, Jido.Instance.NamespaceRegistry) do
          {:ok, pid} when is_pid(pid) -> :ok
          {:ok, pid, _info} when is_pid(pid) -> :ok
          {:error, :running} -> :ok
          {:error, {:already_started, pid}} when is_pid(pid) -> :ok
          other -> raise "cannot restore the namespace registry: #{inspect(other)}"
        end
    end
  end
end
