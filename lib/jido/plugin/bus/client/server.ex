defmodule Jido.Plugin.Bus.Client.Server do
  @moduledoc "Owns one Bus subscription runtime for the Client package."
  use Jido.AgentServer.Plugin

  alias Jido.Plugin.Bus.Client
  alias Jido.Plugin.Bus.Client.Runtime
  alias Jido.Plugin.Init

  @impl true
  def await_ready(runtime, opts) do
    GenServer.call(runtime, :await_ready, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:bus_client_runtime_unavailable, reason}}
  end

  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: Client)
  end
end
