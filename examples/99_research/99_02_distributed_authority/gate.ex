defmodule Jido.Examples.FencedInventory.Gate do
  @moduledoc "Checks external ownership through the public live admission callback."
  use Jido.Plugin

  @impl true
  defdelegate admit(runtime, admission, opts), to: Jido.Examples.FencedInventory.Gate.Server
end

defmodule Jido.Examples.FencedInventory.Gate.Server do
  @behaviour Jido.Plugin

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
