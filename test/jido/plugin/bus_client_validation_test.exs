defmodule Jido.Plugin.BusClientValidationTest do
  use JidoTest.Case, async: true
  alias Jido.Plugin.Bus.Client
  alias Jido.Plugin.Bus.Client.Runtime
  alias Jido.Plugin.Init

  test "invalid subscription options fail before the Client subscribes", %{jido: jido} do
    for {opts, reason} <- [
          {[path: ""], {:invalid_bus_path, ""}},
          {[durable: ""], {:invalid_durable_id, ""}},
          {[retry_delay_ms: 0], {:invalid_retry_delay, 0}},
          {[timeout: 0], {:invalid_timeout, 0}}
        ] do
      init = %Init{
        agent_server: self(),
        agent_id: "client",
        module: Client,
        jido: jido,
        options: [bus: :input] ++ opts
      }

      assert {:error, ^reason} = Runtime.init(init)
    end
  end

  test "an absent Bus produces a subscription failure", %{jido: jido} do
    init = %Init{
      agent_server: self(),
      agent_id: "client",
      module: Client,
      jido: jido,
      options: [bus: :missing]
    }

    assert {:ok, state, {:continue, :subscribe}} = Runtime.init(init)

    assert {:stop, {:bus_subscription_failed, :not_found}, ^state} =
             Runtime.handle_continue(:subscribe, state)

    assert :ok = Runtime.terminate(:normal, state)
  end
end
