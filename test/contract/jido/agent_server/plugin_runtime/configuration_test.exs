Code.require_file("../support.ex", __DIR__)
Code.require_file("configuration_support.ex", __DIR__)

defmodule JidoTest.AgentServer.PluginRuntime.ConfigurationTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.plugin_runtime", async: false

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F
  alias JidoTest.AgentServer.PluginRuntime.ConfigurationSupport, as: Support
  alias Support.{Cache, CacheTwo, Observer, UnsafeCache}

  setup do
    observer = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), observer)
    Map.put(F.setup_runtime(), :observer, observer)
  end

  defp turn(server, directives),
    do: Server.call(server, F.signal(%{mode: :batch, directives: directives}))

  @tag obligation: "jido.agent_server.plugin_runtime.I12"
  test "runtime roots rebuild from committed state and stop after removal", c do
    server = F.start(%{c | agent: Support.agent()})
    assert {:ok, _, _} = turn(server, [Directive.plugin_add(Cache, observer: c.observer)])
    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, first, %{plugin_state: 5, state_version: 1}}
    ref = Process.monitor(first)

    assert {:ok, _, _} =
             turn(server, [Directive.plugin_configure(Cache, observer: c.observer, capacity: 99)])

    assert :ok = Server.await_ready(server)
    assert_receive {:quiescing, ^first, _}
    assert_receive {:DOWN, ^ref, :process, ^first, _}
    assert_receive {:plugin_started, second, %{plugin_state: 5, state_version: 2}}
    assert second != first
    ref = Process.monitor(second)
    assert {:ok, _, _} = turn(server, [Directive.plugin_remove(Cache, state: :discard)])
    assert :ok = Server.await_ready(server)
    assert_receive {:DOWN, ^ref, :process, ^second, _}
    assert Server.agent(server).state == %{count: 3}
    assert Agent.runtime_plugins(Server.agent(server)) == []
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I12"
  test "unsafe changes fail before commit and failed pause resumes the root", c do
    server = F.start(%{c | agent: Support.agent(%{}, [{UnsafeCache, observer: c.observer}])})
    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, root, _}
    assert {:error, _} = turn(server, [Directive.plugin_remove(UnsafeCache)])
    assert Server.status(server).state_version == 0
    assert Process.alive?(root)

    agent =
      Support.agent(%{}, [{Cache, observer: c.observer, pause_mode: :fail}])
      |> Map.put(:id, "other")

    server = F.start(%{c | agent: agent})
    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, root, _}
    assert {:error, _} = turn(server, [Directive.plugin_remove(Cache, state: :discard)])
    assert_receive {:resuming, ^root}
    refute GenServer.call(root, :paused?)
    assert Server.status(server).state_version == 0
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I12"
  test "cancelled preparation resumes the root without publishing a candidate", c do
    agent = Support.agent(%{}, [{Cache, observer: c.observer, gate: true}])
    server = F.start(%{c | agent: agent})
    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, root, _}

    pending =
      Server.submit(
        server,
        F.signal(%{mode: :batch, directives: [Directive.plugin_remove(Cache, state: :discard)]})
      )

    assert_receive {:quiescing, ^root, _}, 1_000
    assert :ok = Server.cancel(server)
    assert {:error, :cancelled} = Server.await(pending)
    assert_receive {:resuming, ^root}
    assert Server.status(server).state_version == 0
    assert Process.alive?(root)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I12"
  test "replacement notifies unchanged Plugins and later commits use the new root", c do
    agent = Support.agent(%{}, [{Observer, observer: c.observer}, {Cache, observer: c.observer}])
    server = F.start(%{c | agent: agent})
    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, first, _}

    assert {:ok, _, _} =
             turn(server, [Directive.plugin_configure(Cache, observer: c.observer, capacity: 2)])

    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, second, %{plugin_state: 5, state_version: 1}}
    assert second != first
    assert_receive {:composition_hook, Observer, nil, 1}
    refute_received {:composition_hook, Cache, _, 1}
    assert {:ok, _, []} = Server.call(server, F.signal())
    assert_receive {:composition_hook, Observer, nil, 2}
    assert_receive {:composition_hook, Cache, ^second, 2}
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I12"
  test "one commit replaces every changed runtime root", c do
    agent =
      Support.agent(%{}, [
        {Cache, observer: c.observer},
        {CacheTwo, observer: c.observer}
      ])

    server = F.start(%{c | agent: agent})
    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, first, %{module: Cache}}
    assert_receive {:plugin_started, second, %{module: CacheTwo}}

    assert {:ok, _, _} =
             turn(server, [
               Directive.plugin_configure(Cache, observer: c.observer, capacity: 2),
               Directive.plugin_configure(CacheTwo, observer: c.observer, capacity: 3)
             ])

    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, replacement_first, %{module: Cache}}
    assert_receive {:plugin_started, replacement_second, %{module: CacheTwo}}
    assert replacement_first != first
    assert replacement_second != second
  end
end
