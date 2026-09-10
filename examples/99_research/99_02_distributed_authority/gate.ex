defmodule Jido.Examples.FencedInventory.Gate do
  @moduledoc "Checks external ownership through the public live admission callback."
  use Jido.Plugin

  alias Jido.Examples.FencedInventory.{Authority, Client}

  def admit(nil, command, _opts) do
    with {:ok, config} <- Client.config(command.agent.id),
         :ok <- Authority.check(config.authority, config.token) do
      {:ok, Jido.Agent.Command.put_plugin_input(command, __MODULE__, config)}
    else
      error ->
        {:error,
         Jido.Error.validation_error("activation has no write authority",
           details: %{cause: error}
         )}
    end
  end
end
