defmodule Jido.AgentServer.DurableTurn.PolicyTest do
  use Jido.Test.Case, async: false
  use Covenant.Case, component: "jido.agent_server.durable_turn", async: false

  alias Jido.AgentServer.Lifecycle
  alias Jido.Flow.Identity
  alias Jido.Test.AgentServer.DurableFixtures, as: F

  defp prepared(agent, type, data) do
    signal = signal(type, data)
    assert {:ok, prepared} = Jido.Agent.Runner.prepare(agent, signal, [])
    {signal, prepared}
  end

  defp data(signal, timeout \\ 1_000) do
    %{
      active: %{
        turn_id: "turn-1",
        source_signal: signal,
        deadline: System.monotonic_time(:millisecond) + timeout
      },
      turn_timeout: timeout
    }
  end

  defp compile_action(module, version) do
    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Jido.Action,
            name: "durable_fingerprint_action"

          def run(input, _context), do: {:ok, Map.put(input, :version, unquote(version))}
        end
      end
    )
  end

  defp compile_flow(module, action, version) do
    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Jido.Flow,
            name: "durable_fingerprint_flow"

          def version, do: unquote(version)

          flow do
            step "step", action: unquote(action), params: %{}
            output result("step")
          end
        end
      end
    )
  end

  defp unload(module) do
    :code.purge(module)
    :code.delete(module)
  end

  @tag obligation: "jido.agent_server.durable_turn.I1"
  test "Flow acceptance keeps only the complete portable recovery receipt" do
    agent = F.Worker.instantiate!(id: "receipt-agent")
    {signal, prepared} = prepared(agent, "request", %{value: 0})

    prepared = %{
      prepared
      | context:
          Map.merge(prepared.context, %{
            custom: %{portable: true},
            turn_id: "remove",
            trace_context: %{remove: true}
          })
    }

    before = System.system_time(:millisecond)
    assert {:ok, receipt} = Lifecycle.accept_continuation(data(signal), prepared)
    after_accept = System.system_time(:millisecond)

    assert receipt.id == "turn-1"
    assert receipt.signal == signal
    assert receipt.admitted_signal == signal
    assert receipt.context == %{custom: %{portable: true}}
    assert receipt.plugin_inputs == %{}
    assert receipt.fingerprint == Identity.executable_digest(F.Flow)
    assert receipt.status == :running
    assert receipt.expires_at in (before + 900)..(after_accept + 1_100)
  end

  @tag obligation: "jido.agent_server.durable_turn.I1"
  test "Flow acceptance reports input validation phase and rejects Action instructions" do
    agent = F.Worker.instantiate!(id: "input-agent")
    {signal, invalid} = prepared(agent, "request", %{value: "bad"})

    assert {:error, %{details: %{phase: :flow_input}}} =
             Lifecycle.accept_continuation(data(signal), invalid)

    {signal, action} = prepared(agent, "increment", %{})
    assert {:error, :not_durable_flow} = Lifecycle.accept_continuation(data(signal), action)
  end

  @tag obligation: "jido.agent_server.durable_turn.I1"
  test "Flow acceptance propagates instruction resolution failure" do
    signal = signal("invalid")

    prepared = %{
      turn: %{executable: String, input: %{}},
      context: %{},
      signal: signal
    }

    assert {:error, _error} = Lifecycle.accept_continuation(data(signal), prepared)
  end

  @tag obligation: "jido.agent_server.durable_turn.I3"
  test "a data Flow has a fingerprint without a module callback" do
    fingerprint = Identity.executable_digest(F.Flow.flow())
    assert is_binary(fingerprint)
    assert byte_size(fingerprint) == 64
  end

  @tag obligation: "jido.agent_server.durable_turn.I3"
  test "the fingerprint covers loaded Flow and Action code" do
    suffix = System.unique_integer([:positive])
    action = Module.concat(__MODULE__, "FingerprintAction#{suffix}")
    flow = Module.concat(__MODULE__, "FingerprintFlow#{suffix}")
    on_exit(fn -> Enum.each([action, flow], &unload/1) end)

    compile_action(action, 1)
    compile_flow(flow, action, 1)
    initial = Identity.executable_digest(flow)

    unload(action)
    compile_action(action, 2)
    action_changed = Identity.executable_digest(flow)
    refute action_changed == initial

    unload(flow)
    compile_flow(flow, action, 2)
    refute Identity.executable_digest(flow) == action_changed
  end

  @tag obligation: "jido.agent_server.durable_turn.I3"
  test "only a running receipt requires Flow reconstruction" do
    agent = F.Worker.instantiate!(id: "terminal-agent")
    assert :ok = Lifecycle.validate_continuation(agent, nil)
    assert :ok = Lifecycle.validate_continuation(agent, %{status: :completed})
    assert :ok = Lifecycle.validate_continuation(agent, %{status: :failed})
    assert :ok = Lifecycle.validate_continuation(agent, %{status: :cancelled})
  end
end
