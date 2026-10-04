defmodule JidoTest.Examples.Persistence.HibernateAndThawTest do
  use JidoTest.AgentCase

  @moduletag group: :persistence

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Persistence.HibernateAndThaw, as: Example
  alias Jido.Persistence.ETS

  test "hibernate stops the old process and thaw restores the saved revision", %{jido: jido} do
    persistence = persistence()
    id = unique_id("hibernate-and-thaw")
    server = start_agent!(jido, Example, id: id, persistence: persistence, restore: false)

    {:ok, signal} = Example.increment_signal(%{amount: 4})
    assert {:ok, %{state: %{count: 4}}} = Server.call(server, signal)
    assert Server.snapshot(server).state_version == 1

    monitor = Process.monitor(server)
    assert :ok = Jido.hibernate(jido, server)
    assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, :hibernate}}, 1_000

    assert {:ok, restored} = Example.thaw(jido, id, persistence)
    assert Server.snapshot(restored) == %{agent: Server.agent(restored), state_version: 1}
    assert Server.agent(restored).state.count == 4
  end

  test "hibernate without persistence fails and keeps the Agent live", %{jido: jido} do
    server = start_agent!(jido, Example)
    before = Server.snapshot(server)

    assert {:error, :persistence_not_configured} = Jido.hibernate(jido, server)
    assert Process.alive?(server)
    assert Server.snapshot(server) == before
  end

  test "thaw rejects a missing required record", %{jido: jido} do
    id = unique_id("missing-thaw")
    assert {:error, :not_found} = Example.thaw(jido, id, persistence())
    assert Jido.whereis_agent(jido, id) == nil
  end

  test "Ref lifetime controls gate idle hibernation and thaw restores it", %{jido: jido} do
    persistence = persistence()
    id = unique_id("idle-hibernate")

    server =
      start_agent!(jido, Example,
        id: id,
        persistence: persistence,
        restore: false,
        idle_timeout: 500
      )

    assert {:ok, ref} = Jido.agent_ref(jido, id)
    assert :ok = Jido.attach(jido, ref)

    assert %{attached: 1, idle_timer?: false} =
             Server.status(server).runtime.lifecycle

    assert :ok = Jido.touch(jido, ref)
    assert :ok = Jido.detach(jido, ref)

    assert %{attached: 0, idle_timer?: true} =
             Server.status(server).runtime.lifecycle

    assert :ok = Jido.touch(jido, ref)
    monitor = Process.monitor(server)

    assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, :idle_timeout}}, 2_000
    assert Jido.whereis_agent(jido, id) == nil

    assert {:ok, restored} = Example.thaw(jido, id, persistence)
    assert Server.snapshot(restored).state_version == 0
    assert Server.agent(restored).state.count == 0

    restored_monitor = Process.monitor(restored)
    assert :ok = Server.stop(restored)
    assert_receive {:DOWN, ^restored_monitor, :process, ^restored, _reason}, 1_000
    assert Jido.agent_count(jido) == 0
  end

  defp persistence do
    table = :"example_hibernate_#{System.unique_integer([:positive])}"
    {ETS, table: table}
  end
end
