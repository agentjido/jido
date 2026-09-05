defmodule Jido.Agent.IdleLifecycleTest do
  use JidoTest.Case, async: true
  alias Jido.AgentServer, as: Server

  defmodule IdleAgent do
    use Jido.Agent, name: "idle_lifecycle"
  end

  defp timer(server) do
    {:idle, state} = :sys.get_state(server)
    state.idle_timer
  end

  test "the default has no idle timer", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, IdleAgent)

    assert %{attached: 0, idle_timeout: :infinity, idle_timer?: false} =
             Server.status(server).runtime.lifecycle
  end

  test "attachment is idempotent and stale timers cannot stop an attached server", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, IdleAgent, idle_timeout: 10_000)
    old_timer = timer(server)
    assert is_reference(old_timer)
    assert :ok = Server.attach(server)
    assert :ok = Server.attach(server)
    assert %{attached: 1, idle_timer?: false} = Server.status(server).runtime.lifecycle
    send(server, {:timeout, old_timer, :agent_idle_timeout})
    assert Server.status(server).phase == :idle
    assert :ok = Server.detach(server)
    assert %{attached: 0, idle_timer?: true} = Server.status(server).runtime.lifecycle
    refute timer(server) == old_timer
  end

  test "the last detach starts idle timing and each live owner is counted", %{jido: jido} do
    owner = start_supervised!({Elixir.Agent, fn -> nil end})
    {:ok, server} = Jido.start_agent(jido, IdleAgent, idle_timeout: 10_000)
    assert :ok = Server.attach(server)
    assert :ok = Server.attach(server, owner)
    assert :ok = Server.detach(server)
    assert %{attached: 1, idle_timer?: false} = Server.status(server).runtime.lifecycle
    assert :ok = Server.detach(server)
    assert Server.status(server).runtime.lifecycle.attached == 1
    assert :ok = Server.detach(server, owner)
    assert %{attached: 0, idle_timer?: true} = Server.status(server).runtime.lifecycle
  end

  test "owner death releases the attachment and a timer stops the server", %{jido: jido} do
    owner = start_supervised!({Elixir.Agent, fn -> nil end})
    {:ok, server} = Jido.start_agent(jido, IdleAgent, idle_timeout: 10_000)
    assert :ok = Server.attach(server, owner)
    Elixir.Agent.stop(owner)
    eventually(fn -> Server.status(server).runtime.lifecycle.attached == 0 end)
    ref = timer(server)
    assert is_reference(ref)
    monitor = Process.monitor(server)
    send(server, {:timeout, ref, :agent_idle_timeout})
    assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, :idle_timeout}}, 1_000
    assert Jido.list_agents(jido) == []
  end

  test "touch replaces the timer and its prior timer message is ignored", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, IdleAgent, idle_timeout: 10_000)
    old_timer = timer(server)
    assert :ok = Server.touch(server)
    new_timer = timer(server)
    assert is_reference(new_timer)
    refute new_timer == old_timer
    send(server, {:timeout, old_timer, :agent_idle_timeout})
    assert Server.status(server).phase == :idle
  end

  test "an actual idle timeout removes the registration without a restart", %{jido: jido} do
    id = unique_id()
    {:ok, server} = Jido.start_agent(jido, IdleAgent, id: id, idle_timeout: 50)
    monitor = Process.monitor(server)
    assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, :idle_timeout}}, 1_000
    assert Jido.whereis_agent(jido, id) == nil
    assert Jido.list_agents(jido) == []
  end

  test "self and dead owners are rejected", %{jido: jido} do
    owner = start_supervised!({Elixir.Agent, fn -> nil end})
    Elixir.Agent.stop(owner)
    {:ok, server} = Jido.start_agent(jido, IdleAgent)
    assert {:error, :cannot_attach_self} = Server.attach(server, server)
    assert {:error, _} = Server.attach(server, owner)
    assert Server.status(server).runtime.lifecycle.attached == 0
  end
end
