defmodule JidoTest.ExampleRuntime do
  @moduledoc "Starts an example Agent and waits for its public readiness boundary."

  def start_agent(jido, agent, opts \\ []) do
    with {:ok, server} <- Jido.start_agent(jido, agent, opts),
         :ok <- Jido.AgentServer.await_ready(server),
         do: {:ok, server}
  end

  # Inspect the current OTP root, not the Agent relationship map.
  def plugin(activation, module) do
    case List.keyfind(Supervisor.which_children(activation), {:plugin, module}, 0) do
      {_, pid, _, _} when is_pid(pid) -> pid
      _ -> nil
    end
  end
end
