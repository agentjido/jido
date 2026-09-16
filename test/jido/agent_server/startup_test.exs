defmodule Jido.AgentServer.StartupTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Error.ValidationError

  defmodule Agent do
    use Jido.Agent, name: "startup_contract"
  end

  defmodule IgnoredRuntimePlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server
    def start_link(_init), do: :ignore
  end

  defmodule IgnoredRuntimePlugin.Server do
    use Jido.AgentServer.Plugin

    def child_spec(init),
      do: %{id: IgnoredRuntimePlugin, start: {IgnoredRuntimePlugin, :start_link, [init]}}
  end

  defmodule HeldIgnoredRuntimePlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server

    def start_link(init) do
      observer = :persistent_term.get({__MODULE__, :observer, init.options[:observer_key]})
      send(observer, {:plugin_starting, init.agent_server, self()})

      receive do
        :return_ignore -> :ignore
      end
    end
  end

  defmodule HeldIgnoredRuntimePlugin.Server do
    use Jido.AgentServer.Plugin

    def child_spec(init),
      do: %{id: HeldIgnoredRuntimePlugin, start: {HeldIgnoredRuntimePlugin, :start_link, [init]}}
  end

  defmodule HeldConstructor do
    def new(opts) do
      observer = opts[:state].observer
      send(observer, {:constructing_agent, self()})

      receive do
        :construct_agent ->
          :persistent_term.put({HeldIgnoredRuntimePlugin, :observer, opts[:id]}, observer)

          definition = %{
            Agent.definition()
            | plugins: [{HeldIgnoredRuntimePlugin, [observer_key: opts[:id]]}]
          }

          Jido.Agent.instantiate(definition, id: opts[:id])
      end
    end
  end

  for entry <- [:instance, :server] do
    test "#{entry} startup preserves the error when the failed Server stops before its caller resumes",
         %{jido: jido} do
      observer = self()
      id = unique_id("delayed-startup-caller")
      on_exit(fn -> :persistent_term.erase({HeldIgnoredRuntimePlugin, :observer, id}) end)

      caller =
        Task.async(fn ->
          case unquote(entry) do
            :instance ->
              Jido.start_agent(jido, HeldConstructor,
                id: id,
                initial_state: %{observer: observer}
              )

            :server ->
              Server.start(
                jido: jido,
                agent: HeldConstructor,
                id: id,
                initial_state: %{observer: observer}
              )
          end
        end)

      assert_receive {:constructing_agent, supervisor}, 1_000
      assert :erlang.suspend_process(caller.pid)

      try do
        send(supervisor, :construct_agent)
        assert_receive {:plugin_starting, server, plugin}, 1_000
        ref = Process.monitor(server)
        send(plugin, :return_ignore)
        assert_receive {:DOWN, ^ref, :process, ^server, _}, 1_000
        refute Process.alive?(server)
      after
        :erlang.resume_process(caller.pid)
      end

      assert {:error,
              {:bootstrap_failed,
               {:plugin_child_start_failed, HeldIgnoredRuntimePlugin, :plugin_child_not_started}}} =
               Task.await(caller)

      eventually(fn -> Jido.whereis_agent(jido, id) == nil end)
    end
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
    definition = %{Agent.definition() | plugins: [{IgnoredRuntimePlugin, []}]}

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
