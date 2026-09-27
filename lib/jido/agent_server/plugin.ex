defmodule Jido.AgentServer.Plugin do
  @moduledoc """
  Provides helpers for the Agent Server callbacks of `Jido.Plugin`.

  These callbacks can reject live commands or return one transient package-owned
  runtime input. It cannot replace pure prepared input or change the Agent,
  source Signal, or caller context. It can also prepare outbound Signals,
  declare one permanent runtime root, gate readiness, receive each Turn commit,
  and dispatch owned Directives after commit. Agent Server owns all tasks,
  limits, restart policy, and settlement. The owner wrapper hosts each root
  generation as temporary so it can restart the root with a fresh committed
  state and state version.
  """

  alias Jido.Plugin.Init

  @doc "Gets one Plugin-owned field from the current complete Agent state."
  @spec state(Init.t(), timeout()) :: {:ok, term()} | {:error, term()}
  def state(%Init{agent_server: agent_server, module: package}, timeout \\ 5_000) do
    Jido.AgentServer.plugin_state(agent_server, package, timeout)
  catch
    :exit, reason -> {:error, {:agent_server_unavailable, reason}}
  end
end
