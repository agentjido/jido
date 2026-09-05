defmodule Jido.Agent.StartupTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Error.ValidationError

  defmodule Agent do
    use Jido.Agent, name: "startup_contract"
  end

  defmodule IgnoredRuntimePlugin do
    use Jido.Plugin

    def child_spec(init), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [init]}}
    def start_link(_init), do: :ignore
  end

  test "dead registry entries are not returned as live Agents", %{jido: jido} do
    id = unique_id("stopped-lookup")
    assert {:ok, pid} = Jido.start_agent(jido, Agent, id: id, restart: :temporary)
    registry = Jido.registry_name(jido)

    partitions =
      for {_id, child, _type, _modules} <- Supervisor.which_children(registry), do: child

    Enum.each(partitions, &:sys.suspend/1)

    try do
      monitor = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
      # Hold cleanup so the stale entry is deterministic.
      assert [{^pid, _}] = Registry.lookup(registry, {:agent, id})
      assert Jido.whereis_agent(jido, id) == nil
      assert Jido.list_agents(jido) == []
      assert Jido.agent_count(jido) == 0
    after
      Enum.each(partitions, &:sys.resume/1)
    end
  end

  test "a Plugin runtime that returns ignore rejects Agent startup", %{jido: jido} do
    id = unique_id("ignored-runtime")
    definition = %{Agent.agent() | plugins: [{IgnoredRuntimePlugin, []}]}

    assert {:error,
            {:bootstrap_failed,
             {:plugin_child_start_failed, IgnoredRuntimePlugin, :plugin_child_not_started}}} =
             Jido.start_agent(jido, definition, id: id)

    eventually(fn -> Jido.whereis_agent(jido, id) == nil end)
  end

  test "invalid startup options return structured errors before starting a child", %{jido: jido} do
    for opts <- [nil, %{}, [:invalid], [id: ""], [id: 7]] do
      assert {:error, %ValidationError{}} = Jido.start_agent(jido, Agent, opts)
    end
  end

  test "start_link links the Server to its caller", %{jido: jido} do
    observer = self()

    {owner, owner_monitor} =
      spawn_monitor(fn ->
        {:ok, server} = Server.start_link(agent: Agent.new!(), jido: jido, register: false)
        send(observer, {:linked_server, server})

        receive do
          :stop -> exit(:owner_stopped)
        end
      end)

    assert_receive {:linked_server, server}
    server_monitor = Process.monitor(server)
    assert {:links, links} = Process.info(server, :links)
    assert owner in links
    send(owner, :stop)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :owner_stopped}
    assert_receive {:DOWN, ^server_monitor, :process, ^server, :owner_stopped}
  end
end
