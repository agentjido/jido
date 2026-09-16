defmodule Jido.Examples.FencedInventory.Gate do
  @moduledoc "Checks external ownership through the public live admission callback."
  use Jido.Plugin, agent_server: __MODULE__.Server
end

defmodule Jido.Examples.FencedInventory.Gate.Server do
  use Jido.AgentServer.Plugin

  alias Jido.Examples.FencedInventory.{Authority, Client}

  @impl true
  def admit(nil, admission, _opts) do
    with {:ok, config} <- Client.config(admission.agent_id),
         :ok <- Authority.check(config.authority, config.token) do
      {:ok, config}
    else
      error ->
        {:error,
         Jido.Error.validation_error("activation has no write authority",
           details: %{cause: error}
         )}
    end
  end
end
