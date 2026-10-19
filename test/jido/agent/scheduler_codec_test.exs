defmodule Jido.Agent.SchedulerCodecTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.AgentServer, as: Server
  alias Jido.Codec.Registry
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
      assert {:ok, json} = Agent.to_json(definition, registry)
      assert json =~ "plugins/scheduler/v1"
      assert {:ok, ^definition} = Agent.from_json(json, registry)
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
    assert {:ok, json} = Agent.to_json(definition, registry)
    missing_plugin = Map.delete(registry.entries, "plugins/scheduler/v1")

    assert {:error, %{details: %{id: "plugins/scheduler/v1", kind: :plugin}}} =
             Agent.from_json(json, missing_plugin)
  end

  test "a complete imported instance retains Plugin state and options" do
    definition = definition(:action)
    instance = Agent.instantiate!(definition, id: "stored-agent", state: %{count: 4})
    assert {:ok, json} = Agent.to_json(instance, registry(definition))
    assert {:ok, ^instance} = Agent.from_json(json, registry(definition))
    assert {:ok, document, temporary} = Codec.encode(instance)
    assert {:ok, ^instance} = Codec.decode(document, temporary)
  end

  test "import validates Scheduler options before startup" do
    definition = definition(:action)
    registry = registry(definition)
    assert {:ok, document} = Codec.encode(definition, registry)
    [extension] = document["agent"]["extensions"]
    data_key = %{"$type" => "symbol", "name" => "data"}
    option_key = %{"$type" => "reference", "kind" => "atom", "id" => "atoms/retry-delay"}
    invalid_options = %{"$type" => "map", "entries" => [[option_key, 0]]}

    entries =
      Enum.map(extension["entries"], fn [key, value] ->
        [key, if(key == data_key, do: invalid_options, else: value)]
      end)

    document = put_in(document, ["agent", "extensions"], [%{extension | "entries" => entries}])

    assert {:error, %{details: %{plugin: Scheduler}}} =
             Agent.from_json(Jason.encode!(document), registry)
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
      "schemas/counter/v1" => {:schema, definition.schema},
      "actions/queue/v1" => {:action, QueueTick},
      "flows/queue/v1" => {:flow, QueueFlow},
      "actions/tick/v1" => {:action, Tick},
      "plugins/scheduler/v1" => {:plugin, Scheduler},
      "atoms/retry-delay" => {:atom, :retry_delay_ms},
      "atoms/count" => {:atom, :count},
      "atoms/scheduler" => {:atom, :scheduler},
      "atoms/cron" => {:atom, :cron}
    })
  end
end
