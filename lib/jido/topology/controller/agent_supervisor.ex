defmodule Jido.Topology.Controller.AgentSupervisor do
  @moduledoc false
  use Supervisor

  def start_link(opts),
    do: Supervisor.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  @impl true
  def init(opts) do
    Supervisor.init(
      [],
      Keyword.put(Keyword.take(opts, [:max_restarts, :max_seconds]), :strategy, :one_for_one)
    )
  end

  def owns?(supervisor, key, pid) do
    Enum.any?(Supervisor.which_children(supervisor), fn
      {^key, ^pid, _, _} -> true
      _ -> false
    end)
  end

  # Remove the spec even if the member is stopped or restarting. A placement
  # move must retire the OTP child before it activates the new owner.
  def retire(supervisor, key) do
    case Supervisor.terminate_child(supervisor, key) do
      :ok -> Supervisor.delete_child(supervisor, key)
      {:error, :not_found} -> :ok
    end
  end
end
