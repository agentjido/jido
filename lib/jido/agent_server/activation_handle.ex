defmodule Jido.AgentServer.ActivationHandle do
  @moduledoc false

  @doc false
  def via(activation) when is_pid(activation), do: {:via, __MODULE__, activation}

  @doc false
  def whereis_name(activation) when is_pid(activation) do
    Jido.AgentServer.Supervisor.live_worker(activation) || :undefined
  end

  @doc false
  def register_name(_activation, _pid), do: :no

  @doc false
  def unregister_name(_activation), do: :ok

  @doc false
  def send(activation, message) do
    case whereis_name(activation) do
      pid when is_pid(pid) -> Kernel.send(pid, message)
      :undefined -> exit({:badarg, {__MODULE__, :send, [activation, message]}})
    end
  end
end
