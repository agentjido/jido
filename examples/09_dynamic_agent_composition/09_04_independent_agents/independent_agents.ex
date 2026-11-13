defmodule Jido.Examples.IndependentAgents do
  @moduledoc "Starts and addresses independent Worker Agents in one Jido instance."

  alias Jido.Examples.Worker

  def start(instance, id), do: Jido.start_agent(instance, Worker, id: id)

  def calculate(server, request_id, value) do
    with {:ok, signal} <- Worker.calculate_signal(%{request_id: request_id, value: value}),
         do: Jido.AgentServer.call(server, signal)
  end
end
