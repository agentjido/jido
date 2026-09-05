defmodule Jido.AgentServerContextTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule ContextPlugin do
    use Jido.Plugin

    @impl true
    def admit(_runtime, command, _opts) do
      send(command.context.observer, {:context_admitted, command.context, command.signal})
      {:ok, %{command | context: Map.put(command.context, :admitted, true)}}
    end

    @impl true
    def prepare(command, _opts) do
      {:ok, %{command | context: Map.put(command.context, :prepared, true)}}
    end

    @impl true
    def state_spec(_opts), do: {:context_plugin, Zoi.integer() |> Zoi.default(0)}

    @impl true
    def update_state(state, _directives, _opts), do: {:ok, state + 1}

    @impl true
    def prepare_dispatch(_runtime, signal, context, _opts) do
      send(context.turn_context.observer, {:context_dispatch, signal, context})
      {:ok, signal}
    end

    def child_spec(init),
      do: Supervisor.child_spec({Elixir.Agent, fn -> init end}, id: __MODULE__)
  end

  defmodule Emit do
    use Jido.Action,
      name: "server_context_emit",
      schema: Zoi.object(%{value: Zoi.integer()})

    @impl true
    def run(%{value: value}, context) do
      send(context.observer, {:context_executed, context})
      output = Signal.new!("context.output", %{value: value}, source: "/context-test")
      {:ok, %{context.agent_state | value: value}, [Jido.Agent.Directive.emit(output)]}
    end
  end

  defmodule Agent do
    use Jido.Agent,
      name: "server_context_agent",
      schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}),
      routes: [{"context.input", Emit}],
      plugins: [ContextPlugin]
  end

  test "context crosses Plugin admission and execution but is not copied to state or Signals", %{
    jido: jido
  } do
    {:ok, server} =
      Jido.start_agent(jido, Agent,
        id: unique_id(),
        default_dispatch: {:pid, target: self()}
      )

    command = signal("context.input", %{value: 7})
    private_request = make_ref()

    assert {:ok, committed} =
             Server.call(server, command,
               context: %{
                 observer: self(),
                 private_request: private_request,
                 jido: :caller_cannot_replace_owner,
                 partition: :caller_cannot_replace_partition
               }
             )

    assert_receive {:context_admitted, admitted, ^command}
    assert admitted.private_request == private_request
    assert admitted.jido == jido
    assert admitted.partition == nil
    assert_receive {:context_executed, executed}
    assert executed.admitted
    assert executed.prepared
    assert executed.private_request == private_request
    assert executed.signal.data == command.data
    assert executed.agent_state == %{value: 0, context_plugin: 0}

    assert_receive {:context_dispatch, output, dispatch}
    assert dispatch.turn_context.private_request == private_request
    assert dispatch.source_signal == command
    assert dispatch.effective_signal.data == command.data
    assert dispatch.plugin_state == 1
    assert_receive {:signal, delivered}
    assert delivered == output
    assert delivered.data == %{value: 7}
    refute Map.has_key?(delivered.extensions, "private_request")
    assert committed.state == %{value: 7, context_plugin: 1}
    eventually(fn -> Server.status(server).phase == :idle end)
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
  end
end
