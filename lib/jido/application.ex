defmodule Jido.Application do
  @moduledoc false
  use Application

  alias Jido.RuntimeDefaults

  @doc false
  def start(_type, _args) do
    children = [
      # System-wide supervisor for fire-and-forget async tasks
      {Task.Supervisor,
       name: Jido.SystemTaskSupervisor, max_children: RuntimeDefaults.system_task_max_children()},
      # ETS table heir process to retain tables if owner crashes
      Jido.Storage.ETS.Heir,
      # Dedicated owner for ETS-backed storage tables
      Jido.Storage.ETS.Owner,
      # Telemetry handler for agent and strategy metrics
      Jido.Telemetry
    ]

    # Register essential signal extensions before starting supervision tree
    register_signal_extensions()

    case Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor) do
      {:ok, _pid} = ok ->
        # Discovery needs Jido.SystemTaskSupervisor to be running first.
        _ = Jido.Discovery.init_async()
        ok

      other ->
        other
    end
  end

  # Ensure critical signal extensions are registered
  defp register_signal_extensions do
    extensions = [
      Jido.Signal.Ext.Trace,
      Jido.Signal.Ext.Dispatch,
      Jido.Signal.Ext.Target
    ]

    for ext <- extensions do
      Code.ensure_loaded(ext)
      Jido.Signal.Ext.Registry.register(ext)
    end

    :ok
  rescue
    # Gracefully handle missing modules during compilation or testing
    _ -> :ok
  end
end
