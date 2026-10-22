defmodule Jido.Agent.SchedulerCodecTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Authoring.Registry
  alias Jido.Plugin.Scheduler

  defmodule QueueTick do
    use Jido.Action, name: "codec_queue_tick"

    def run(_, %{agent_state: state}) do
      tick = Jido.Signal.new!("codec.tick", %{}, source: "/test/codec")
      {:ok, state, [Scheduler.schedule(0, tick)]}
    end
  end

  defmodule QueueFlow do
    use Jido.Flow, name: "codec_queue_flow"

    flow do
      step "queue", action: QueueTick, params: %{}
      output result("queue")
    end
  end

  defmodule Tick do
    use Jido.Action, name: "codec_tick"
    def run(_, %{agent_state: state}), do: {:ok, %{state | count: state.count + 1}}
  end

  for kind <- [:action, :flow] do
    test "an imported #{kind} route dispatches through the Scheduler Plugin", %{jido: jido} do
      definition = definition(unquote(kind))
      registry = registry(definition)
      assert {:ok, json} = JidoTest.AgentRegistry.encode_json(definition, registry)
      assert json =~ "plugins/scheduler"
      assert {:ok, ^definition} = JidoTest.AgentRegistry.decode_json(json, registry)
      assert definition.id == nil
      assert definition.state == nil

      assert [{Scheduler, [retry_delay_ms: 17]}] = Agent.runtime_plugins(definition)
      instance = Agent.instantiate!(definition, id: unique_id("json-scheduler"))
      assert instance.state == %{count: 0, scheduler: %{cron: %{}}}

      assert {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, instance)
      assert {:ok, %{cron: %{}}} = Server.plugin_state(server, Scheduler)

      assert {:ok, committed, [%Scheduler.Schedule{}]} =
               Server.call(server, signal("codec.queue"))

      assert committed.state.count == 0
      eventually(fn -> Server.agent(server).state.count == 1 end)
      assert Server.snapshot(server).state_version == 2

      scheduler = JidoTest.AgentServerAssertions.plugin(server, Scheduler).pid
      scheduler_monitor = Process.monitor(scheduler)
      server_monitor = Process.monitor(server)
      assert :ok = Jido.stop_agent(jido, server)
      assert_receive {:DOWN, ^scheduler_monitor, :process, ^scheduler, _}
      assert_receive {:DOWN, ^server_monitor, :process, ^server, _}
    end
  end

  test "import requires the trusted Scheduler reference" do
    definition = definition(:action)
    registry = registry(definition)
    assert {:ok, json} = JidoTest.AgentRegistry.encode_json(definition, registry)
    missing_plugin = Map.delete(registry.entries, {"plugins/scheduler", 1})

    assert {:error,
            [
              %Jido.Authoring.Issue{
                details: %{identifier: "plugins/scheduler", kind: :plugin}
              }
            ]} =
             JidoTest.AgentRegistry.decode_json(json, missing_plugin)
  end

  test "an imported instance becomes a definition and retains Plugin options" do
    definition = definition(:action)
    instance = Agent.instantiate!(definition, id: "stored-agent", state: %{count: 4})
    assert {:ok, json} = JidoTest.AgentRegistry.encode_json(instance, registry(definition))
    assert {:ok, ^definition} = JidoTest.AgentRegistry.decode_json(json, registry(definition))
    assert {:ok, document} = JidoTest.AgentRegistry.encode(instance, registry(definition))
    assert {:ok, ^definition} = JidoTest.AgentRegistry.decode(document, registry(definition))
  end

  test "import validates Scheduler options before startup" do
    definition = definition(:action)
    registry = registry(definition)
    assert {:ok, document} = JidoTest.AgentRegistry.encode(definition, registry)
    [extension] = document["definition"]["extensions"]
    option_key = %{"$type" => "atom", "id" => "atoms/retry-delay", "vsn" => 1}

    invalid_options = %{
      "$type" => "map",
      "entries" => [%{"key" => option_key, "value" => 0}]
    }

    document =
      put_in(document, ["definition", "extensions"], [%{extension | "data" => invalid_options}])

    assert {:error,
            [
              %Jido.Authoring.Issue{
                code: :invalid_document,
                message: "Scheduler retry_delay_ms is invalid"
              }
            ]} = JidoTest.AgentRegistry.decode_json(Jason.encode!(document), registry)
  end

  defp definition(kind) do
    target = if kind == :action, do: QueueTick, else: QueueFlow

    Agent.define!(%{
      name: "json_scheduler",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      extensions: [
        %{
          id: Scheduler.id(),
          provider: Scheduler,
          vsn: Scheduler.vsn(),
          data: %{retry_delay_ms: 17}
        }
      ],
      routes: [
        %{path: "codec.queue", handler: %{kind: kind, target: target}},
        %{path: "codec.tick", handler: %{kind: :action, target: Tick}}
      ]
    })
  end

  defp registry(definition) do
    Registry.new!(%{
      {"schemas/counter", 1} => {:schema, definition.schema},
      {"actions/queue", 1} => {:action, QueueTick},
      {"flows/queue", 1} => {:flow, QueueFlow},
      {"actions/tick", 1} => {:action, Tick},
      {"plugins/scheduler", 1} => {:plugin, Scheduler},
      {"atoms/retry-delay", 1} => {:atom, :retry_delay_ms},
      {"atoms/count", 1} => {:atom, :count},
      {"atoms/scheduler", 1} => {:atom, :scheduler},
      {"atoms/cron", 1} => {:atom, :cron}
    })
  end
end
