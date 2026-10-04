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

  defp persistence do
    table = :"example_hibernate_#{System.unique_integer([:positive])}"
    {ETS, table: table}
  end
end
