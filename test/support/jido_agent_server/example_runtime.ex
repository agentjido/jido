defmodule Jido.Test.AgentServer.ExampleRuntime do
  @moduledoc "Starts an example Agent and waits for its public readiness boundary."

  def start_agent(jido, agent, opts \\ []) do
    with {:ok, server} <- Jido.start_agent(jido, agent, opts),
         :ok <- Jido.AgentServer.await_ready(server),
         do: {:ok, server}
  end

  @doc false
  def activation(server) do
    {_phase, data} = :sys.get_state(server)
    data.activation
  end

  @doc false
  def plugin_state(server, plugin, timeout \\ 5_000) do
    Jido.AgentServer.Worker.plugin_state(server, plugin, timeout)
  end

  # Inspect the current OTP root, not the Agent relationship map.
  def plugin(activation, module) do
    plugin_supervisor = Jido.AgentServer.Supervisor.plugin_supervisor(activation)

    case plugin_supervisor &&
           List.keyfind(Supervisor.which_children(plugin_supervisor), {:plugin, module}, 0) do
      {_, pid, _, _} when is_pid(pid) -> pid
      _ -> nil
    end
  catch
    :exit, _reason -> nil
  end
end
