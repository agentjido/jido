defmodule JidoTest.Agent.SpawnRegistryTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer.SpawnRegistry
  alias Jido.RuntimeStore

  test "a live child owns its tag until retirement, and older generations stay closed", %{
    jido: jido
  } do
    child = start_supervised!({Elixir.Agent, fn -> :child end})
    first = parent(1)
    second = %{first | spawn_ref: {2, make_ref()}}

    assert :ok = SpawnRegistry.claim(jido, first)
    assert :ok = SpawnRegistry.started(jido, first, child)
    assert {:existing, ^child} = SpawnRegistry.claim(jido, first)
    assert {:error, :child_tag_in_use} = SpawnRegistry.claim(jido, second)
    assert :ok = SpawnRegistry.retire(jido, child)
    assert :closed = SpawnRegistry.claim(jido, first)

    stop_supervised!(Elixir.Agent)
    assert :ok = SpawnRegistry.claim(jido, second)
    assert :closed = SpawnRegistry.claim(jido, first)
    assert {:error, :spawn_request_closed} = SpawnRegistry.started(jido, first, self())
  end

  test "a failed start closes only the matching request", %{jido: jido} do
    first = parent(1)
    second = %{first | spawn_ref: {2, make_ref()}}

    assert :ok = SpawnRegistry.claim(jido, first)
    assert :ok = SpawnRegistry.failed(jido, first)
    assert :closed = SpawnRegistry.claim(jido, first)
    assert :ok = SpawnRegistry.claim(jido, second)
    assert :ok = SpawnRegistry.failed(jido, first)
    assert :ok = SpawnRegistry.started(jido, second, self())
    assert {:existing, pid} = SpawnRegistry.claim(jido, second)
    assert pid == self()
    assert :ok = SpawnRegistry.retire(jido, spawn(fn -> :ok end))
  end

  test "registry restart restores live claims and retirement lookup", %{jido: jido} do
    child = start_supervised!({Elixir.Agent, fn -> :child end})
    owner = parent(1)
    assert :ok = SpawnRegistry.claim(jido, owner)
    assert :ok = SpawnRegistry.started(jido, owner, child)

    :ok = Supervisor.terminate_child(jido, SpawnRegistry)
    assert {:ok, _} = Supervisor.restart_child(jido, SpawnRegistry)
    assert {:existing, ^child} = SpawnRegistry.claim(jido, owner)
    assert :ok = SpawnRegistry.retire(jido, child)
    assert :closed = SpawnRegistry.claim(jido, owner)
  end

  test "parent death removes only its claims and stale monitor messages are ignored", %{
    jido: jido
  } do
    owner = start_supervised!({Elixir.Agent, fn -> :owner end}, id: :owner)
    first = %{parent(1) | pid: owner}
    other = parent(1)
    assert :ok = SpawnRegistry.claim(jido, first)
    assert :ok = SpawnRegistry.claim(jido, other)
    assert :ok = SpawnRegistry.started(jido, other, self())

    registry = Process.whereis(SpawnRegistry.name(jido))
    send(registry, {:DOWN, make_ref(), :process, self(), :normal})
    send(registry, {:DOWN, make_ref(), :process, self(), :noconnection})
    assert {:existing, pid} = SpawnRegistry.claim(jido, other)
    assert pid == self()

    stop_supervised!(:owner)

    eventually(fn ->
      entries = RuntimeStore.list(jido, :agent_spawn_requests)
      length(entries) == 1 and elem(hd(entries), 0) == {self(), :worker}
    end)

    assert {:existing, ^pid} = SpawnRegistry.claim(jido, other)
  end

  defp parent(generation) do
    %{pid: self(), tag: :worker, spawn_ref: {generation, make_ref()}}
  end
end
