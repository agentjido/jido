defmodule Jido.Plugin.Bus.ClientRuntimeTest do
  use JidoTest.Case, async: true
  alias Jido.Plugin.Bus.Client
  alias Jido.Plugin.Bus.Client.Runtime
  alias Jido.Plugin.Init
  alias Jido.Signal.Bus

  test "readiness reconnects to a replaced Bus before its retry timer fires", %{jido: jido} do
    bus = start_supervised!({Bus, name: :ready_bus, jido: jido}, id: :ready_bus)

    init = %Init{
      agent_server: self(),
      agent_id: "client",
      module: Client,
      jido: jido,
      options: [bus: :ready_bus, retry_delay_ms: 60_000]
    }

    client = start_supervised!({Runtime, init})
    assert :ok = Client.Server.await_ready(client, [])
    monitor = Process.monitor(bus)
    stop_supervised!(:ready_bus)
    assert_receive {:DOWN, ^monitor, :process, ^bus, _}
    eventually(fn -> :sys.get_state(client).bus == nil end)
    stale_token = :sys.get_state(client).reconnect_token
    replacement = start_supervised!({Bus, name: :ready_bus, jido: jido}, id: :ready_bus)

    assert :ok = Client.Server.await_ready(client, [])
    state = :sys.get_state(client)
    assert state.bus == replacement
    assert is_binary(state.subscription_id)
    send(client, {:reconnect, stale_token})
    assert :sys.get_state(client).subscription_id == state.subscription_id
  end

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

  test "Bus scope defaults preserve explicit global and instance options", %{jido: jido} do
    for {opts, lookup_opts} <- [
          {[], [jido: jido]},
          {[jido: nil], []},
          {[jido: __MODULE__.OtherInstance], [jido: __MODULE__.OtherInstance]}
        ] do
      init = %Init{
        agent_server: self(),
        agent_id: "client",
        module: Client,
        jido: jido,
        options: [bus: :input] ++ opts
      }

      assert {:ok, state, {:continue, :subscribe}} = Runtime.init(init)
      assert state.config.lookup_opts == lookup_opts
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
