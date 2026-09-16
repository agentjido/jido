defmodule Jido.Plugin.Heartbeat.Server do
  @moduledoc "Owns the periodic Signal runtime for the Heartbeat package."
  use Jido.AgentServer.Plugin

  alias Jido.Plugin.Heartbeat
  alias Jido.Plugin.Heartbeat.Runtime
  alias Jido.Plugin.Init

  @impl true
  def validate_options(opts) do
    case Heartbeat.configuration(opts) do
      {:ok, _config} ->
        :ok

      {:error, reason} ->
        {:error,
         Jido.Error.validation_error("Heartbeat Plugin options are invalid",
           kind: :config,
           details: %{reason: reason}
         )}
    end
  end

  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: Heartbeat)
  end
end
