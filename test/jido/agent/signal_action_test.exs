defmodule Jido.Agent.SignalActionTest do
  use ExUnit.Case, async: true

  defmodule CreateThread do
    use Jido.SignalAction,
      name: "routed_create_thread",
      description: "Create a chat thread after commit",
      vsn: 1,
      input: [type: "chat.thread.create", schema: Zoi.object(%{name: Zoi.string()})],
      output: [type: "chat.thread.created", schema: Zoi.object(%{id: Zoi.string()})]

    @impl Jido.Action
    def run(_data, context) do
      send(context.probe, {:created_thread, Map.get(context, :committed_version)})
      {:ok, %{id: "thread-1"}}
    end
  end

  defmodule Add do
    use Jido.SignalAction,
      name: "signal_action_add",
      description: "Add to Agent state",
      vsn: 1,
      input: [type: "counter.add", schema: Zoi.object(%{amount: Zoi.integer()})],
      output: Zoi.object(%{count: Zoi.integer()})

    @impl Jido.Action
    def run(%{amount: amount}, %{agent_state: state}), do: {:ok, %{count: state.count + amount}}
  end

  defmodule Deliver do
    use Jido.Agent.Directive
    defstruct [:action, :request]
  end

  defmodule Execute do
    use Jido.Action, name: "defer_signal_action"

    @impl Jido.Action
    def run(data, %{agent_state: state, signal: request}) do
      count = if data.name == "reject", do: :invalid, else: state.count + 1
      {:ok, %{state | count: count}, [%Deliver{action: CreateThread, request: request}]}
    end
  end

  defmodule Delivery do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [Deliver]

    @impl true
    def dispatch(_runtime, %Deliver{action: action, request: request}, context, _opts) do
      exec_context = Map.put(context.turn_context, :committed_version, context.state_version)
      {:ok, data} = Jido.Exec.run(action, request.data, exec_context)
      {:ok, reply} = action.reply(request, data, source: "/chat")
      send(context.turn_context.probe, {:completed_thread, context.state_version, request, reply})
      :ok
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "signal_action_counter"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/counter"
      route Add, as: :add, defaults: %{amount: 1}
    end
  end

  defmodule Deferred do
    use Jido.Agent, name: "deferred_signal_action"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    plugins do
      plugin Jido.Agent.SignalActionTest.Delivery
    end

    routes do
      signal_source "/chat"
      route CreateThread, Execute, as: :create_thread
    end
  end

  test "a module route lowers to an ordinary Action route" do
    assert [route] = Counter.definition().routes
    assert route.path == Add.type()
    assert route.handler == %{kind: :action, target: Add}
    assert route.defaults == %{amount: 1}

    assert {:ok, signal} = Counter.add_signal(%{amount: 2})
    assert signal.type == Add.type()

    assert {:ok, %{state: %{count: 2}}, []} =
             Counter.cmd(Counter.instantiate!(id: "counter"), signal)

    assert {:ok, signal} = Counter.add_signal(%{})

    assert {:ok, %{state: %{count: 1}}, []} =
             Counter.cmd(Counter.instantiate!(id: "counter"), signal)
  end

  test "the two-module form selects its handler without deferred work" do
    request = CreateThread.new!(%{name: "General"}, source: "/caller")
    assert [route] = Deferred.definition().routes
    assert route.path == CreateThread.type()
    assert route.handler == %{kind: :action, target: Execute}

    assert {:ok, %{state: %{count: 1}}, [%Deliver{request: ^request}]} =
             Deferred.cmd(Deferred.instantiate!(id: "deferred"), request,
               context: %{probe: self()}
             )

    refute_received {:created_thread, _}
    refute_received {:completed_thread, _, _, _}
  end

  test "module routes use the same public definition and Codec contracts" do
    definition = Counter.definition()
    registry = JidoTest.AgentRegistry.for(definition)
    assert {:ok, document} = JidoTest.AgentRegistry.encode(definition, registry)

    assert {:ok, ^definition} =
             JidoTest.AgentRegistry.decode(JSON.decode!(JSON.encode!(document)), registry)
  end

  test "invalid module routes fail at declaration" do
    for {route, error, message} <- [
          {"route String", ArgumentError, ~r/requires a Jido.SignalAction/},
          {"route MissingSignalAction", ArgumentError, ~r/could not load module/},
          {"route #{inspect(CreateThread)}, via: nil", CompileError, ~r/Unknown route options/},
          {"route \"chat.create\", via: String", CompileError, ~r/Unknown route options/},
          {"route #{inspect(CreateThread)}, String", CompileError,
           ~r/Expected an Action or Flow module/},
          {"route #{inspect(CreateThread)} do transform signal do {:ok, signal} end end",
           CompileError, ~r/does not accept an inline handler/}
        ] do
      assert_raise error, message, fn ->
        module = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

        Code.compile_string("""
        defmodule #{inspect(module)} do
          use Jido.Agent, name: "invalid"
          routes do
            #{route}
          end
        end
        """)
      end
    end
  end
end

defmodule Jido.Agent.SignalActionRuntimeTest do
  use JidoTest.Case, async: true

  alias Jido.{AgentServer, Signal}
  alias Jido.Agent.SignalActionTest.{CreateThread, Deferred}

  test "via keeps Action execution after a live Agent commit", %{jido: jido} do
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, Deferred)
    request = CreateThread.new!(%{name: "General"}, source: "/caller")

    assert {:ok, %{state: %{count: 1}}, _} =
             AgentServer.call(server, request, context: %{probe: self()})

    assert_receive {:created_thread, 1}, 1_000
    assert_receive {:completed_thread, 1, ^request, reply}, 1_000
    assert reply.type == "chat.thread.created"
    assert reply.data == %{id: "thread-1"}
    assert Signal.get_context(reply, "jidocausationid") == request.id
    assert AgentServer.status(server).state_version == 1
  end

  test "a failed commit does not execute the SignalAction", %{jido: jido} do
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, Deferred)
    request = CreateThread.new!(%{name: "reject"}, source: "/caller")

    assert {:error, _} = AgentServer.call(server, request, context: %{probe: self()})
    assert AgentServer.status(server).state_version == 0
    refute_received {:created_thread, _}
    refute_received {:completed_thread, _, _, _}
  end
end
