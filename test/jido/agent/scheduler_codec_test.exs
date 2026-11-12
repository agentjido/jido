defmodule Jido.Agent.SchedulerCodecTest do
  use Jido.Test.Case, async: true

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Catalog
  alias Jido.Plugin.Scheduler

  defmodule QueueTick do
    use Jido.Action,
      name: "codec_queue_tick"

    def run(_, %{agent_state: state}) do
      tick = Jido.Signal.new!("codec.tick", %{}, source: "/test/codec")
      {:ok, state, [Scheduler.schedule(0, tick)]}
    end
  end

  defmodule QueueFlow do
    use Jido.Flow,
      name: "codec_queue_flow"

    flow do
      step "queue", action: QueueTick, params: %{}
      output result("queue")
    end
  end

  defmodule Tick do
    use Jido.Action,
      name: "codec_tick"

    def run(_, %{agent_state: state}), do: {:ok, %{state | count: state.count + 1}}
  end

  for kind <- [:action, :flow] do
    test "an imported #{kind} route dispatches through the Scheduler Plugin", %{jido: jido} do
      definition = definition(unquote(kind))
      registry = registry(definition)
      assert {:ok, json} = Jido.Test.AgentServer.Registry.encode_json(definition, registry)
      assert json =~ "plugins/scheduler"
      assert {:ok, ^definition} = Jido.Test.AgentServer.Registry.decode_json(json, registry)
      assert definition.id == nil
      assert definition.state == nil

      assert [{Scheduler, [retry_delay_ms: 17]}] = Agent.Plugin.declarations(definition)
      instance = Agent.instantiate!(definition, id: unique_id("json-scheduler"))
      assert instance.state == %{count: 0, scheduler: %{cron: %{}}}

      assert {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(jido, instance)
      assert Server.snapshot(server).agent.state.scheduler == %{cron: %{}}

      assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, effects: :pending}} =
               Server.call(server, signal("codec.queue"))

      assert Server.snapshot(server).agent.state.count == 0
      eventually(fn -> Server.snapshot(server).agent.state.count == 1 end)
      assert Server.snapshot(server).agent_revision == 2

      scheduler = Jido.Test.AgentServer.Assertions.plugin(server, Scheduler).pid
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
    assert {:ok, json} = Jido.Test.AgentServer.Registry.encode_json(definition, registry)

    missing_plugin =
      registry
      |> Catalog.list()
      |> Enum.reject(&(&1.id == "plugins/scheduler" and &1.vsn == 1))
      |> Catalog.new!()

    assert {:error,
            [
              %Jido.Codec.Issue{
                details: %{identifier: "plugins/scheduler"}
              }
            ]} =
             Jido.Test.AgentServer.Registry.decode_json(json, missing_plugin)
  end

  test "an imported instance becomes a definition and retains Plugin options" do
    definition = definition(:action)
    instance = Agent.instantiate!(definition, id: "stored-agent", state: %{count: 4})
    assert {:ok, json} = Jido.Test.AgentServer.Registry.encode_json(instance, registry(definition))
    assert {:ok, ^definition} = Jido.Test.AgentServer.Registry.decode_json(json, registry(definition))
    assert {:ok, document} = Jido.Test.AgentServer.Registry.encode(instance, registry(definition))
    assert {:ok, ^definition} = Jido.Test.AgentServer.Registry.decode(document, registry(definition))
  end

  test "import validates Scheduler options before startup" do
    definition = definition(:action)
    registry = registry(definition)
    assert {:ok, document} = Jido.Test.AgentServer.Registry.encode(definition, registry)
    [plugin] = document["definition"]["plugins"]
    option_key = %{"$type" => "atom", "id" => "atoms/retry-delay", "vsn" => 1}

    invalid_options = %{
      "$type" => "map",
      "entries" => [%{"key" => option_key, "value" => 0}]
    }

    document =
      put_in(document, ["definition", "plugins"], [%{plugin | "data" => invalid_options}])

    assert {:error,
            [
              %Jido.Codec.Issue{
                code: :invalid_document,
                message: "Scheduler retry_delay_ms is invalid"
              }
            ]} = Jido.Test.AgentServer.Registry.decode_json(Jason.encode!(document), registry)
  end

  defp definition(kind) do
    target = if kind == :action, do: QueueTick, else: QueueFlow

    Agent.define!(%{
      name: "json_scheduler",
      schema: Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)}),
      plugins: [
        %{
          id: Scheduler.id(),
          provider: Scheduler,
          vsn: Scheduler.vsn(),
          data: %{retry_delay_ms: 17}
        }
      ],
      routes: [
        %{
          path: "codec.queue",
          handler: %{kind: kind, target: target},
          state: %{source: :output, path: []}
        },
        %{
          path: "codec.tick",
          handler: %{kind: :action, target: Tick},
          state: %{source: :output, path: []}
        }
      ]
    })
  end

  defp registry(definition) do
    Catalog.from_targets!(__MODULE__, :jido, %{
      {"schemas/counter", 1} => definition.schema,
      {"actions/queue", 1} => QueueTick,
      {"flows/queue", 1} => QueueFlow,
      {"actions/tick", 1} => Tick,
      {"plugins/scheduler", 1} => Scheduler,
      {"atoms/retry-delay", 1} => :retry_delay_ms,
      {"atoms/count", 1} => :count,
      {"atoms/scheduler", 1} => :scheduler,
      {"atoms/cron", 1} => :cron
    })
  end
end
