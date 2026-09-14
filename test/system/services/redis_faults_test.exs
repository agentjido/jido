Code.require_file("../support/case.exs", __DIR__)

defmodule JidoTest.System.Services.RedisFaults do
  use JidoTest.System.Case, async: false
  @moduletag :service
  @moduletag adapter: :redis
  alias Jido.AgentServer, as: Server
  alias JidoTest.RecoverableDeliveryAgent, as: Probe
  alias JidoTest.RecoverableDeliverySink, as: Sink
  alias JidoTest.System.{Observability, RedisServer}

  setup do
    {:ok, supervisor} = ExUnit.fetch_test_supervisor()

    {RedisServer, redis, _, _} =
      List.keyfind(Supervisor.which_children(supervisor), RedisServer, 0)

    {socket, os_pid} = GenServer.call(redis, :connection)
    {:ok, redis: redis, socket: socket, os_pid: os_pid}
  end

  test "SIGKILL and AOF restart retain completed effects and the checkpoint revision", c do
    server = start_agent(c)
    assert {:ok, _} = Probe.record_and_deliver(server, "saved", 7)
    completed(c, server, %{"saved" => 7})
    snapshot = Server.snapshot(server)
    kill_agent(c, server)
    {socket, replacement_os_pid} = GenServer.call(c.redis, :crash_restart, 10_000)
    assert socket == c.socket
    assert replacement_os_pid != c.os_pid
    assert {:ok, "PONG"} = RedisServer.command(socket, ["PING"])
    assert {:ok, stored, 2} = load(c, snapshot.agent.id)
    assert stored == snapshot.agent
    restored = start_agent(c, id: stored.id, restore: :required)
    assert Server.snapshot(restored) == snapshot
    stop_agent(c, restored)
    assert Sink.records(c.jido) == %{"saved" => 7}
    assert length(Sink.attempts(c.jido)) == 1
  end

  test "a lost Redis socket reply after Lua commit fences execution and restores saved intent",
       c do
    control = start_supervised!({Agent, fn -> false end}, id: :network_fault)

    command = fn parts ->
      drop? = if hd(parts) == "EVAL", do: Agent.get_and_update(control, &{&1, false}), else: false

      if drop?,
        do: RedisServer.command_without_reply(c.socket, parts),
        else: RedisServer.command(c.socket, parts)
    end

    store = {Jido.Persistence.Redis, command_fn: command, prefix: "system"}
    server = start_agent(c, persistence: store)
    id = Server.agent(server).id
    monitors = monitor_agent_tree(c, server)
    Agent.update(control, fn _ -> true end)
    signal = Probe.record_and_deliver_signal!("uncertain", 7)

    assert {:error, {:persistence_failed, {:indeterminate, :closed}}} =
             Server.call(server, signal)

    await_down(monitors)
    assert_empty_agent_pool(c)
    assert Sink.attempts(c.jido) == []

    assert {:ok, %{state: %{value: 7, delivery: %{pending: %{"uncertain" => 7}}}}, 1} =
             load(c, id)

    Observability.assert_persistence(c.observer, :indeterminate)
    restored = start_agent(c, id: id, restore: :required)
    completed(c, restored, %{"uncertain" => 7})
    stop_agent(c, restored)
    assert Sink.records(c.jido) == %{"uncertain" => 7}
    assert length(Sink.attempts(c.jido)) == 1
  end
end
