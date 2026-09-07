defmodule Jido.AgentServer.RuntimeBoundaryTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.ParentRef
  alias JidoTest.AgentFixtures

  @moduletag capture_log: true

  defmodule EmitMany do
    use Jido.Action, name: "runtime_boundary_emit_many"

    def run(%{count: count}, %{agent_state: state}) do
      signal = Jido.Signal.new!("boundary.output", %{}, source: "/boundary")
      directives = List.duplicate(Directive.emit(signal, {:noop, []}), count)
      {:ok, %{state | count: state.count + 1}, directives}
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "runtime_boundary_agent"

    agent do
      schema Zoi.object(%{
               count: Zoi.integer() |> Zoi.default(0),
               history: Zoi.list(Zoi.string()) |> Zoi.default([])
             })
    end

    routes do
      route "boundary.fail", AgentFixtures.Fail
      route "jido.agent.error", AgentFixtures.Fail
      route "boundary.emit", EmitMany
      route "boundary.hold", AgentFixtures.BlockingAdd
    end
  end

  defmodule FailedExec do
    def run_async(_, _, _, opts) do
      case Keyword.fetch!(opts, :failure) do
        :raise -> raise "Exec unavailable"
        :throw -> throw(:exec_unavailable)
      end
    end

    def handle_message(_, _), do: :ignore
    def cancel(_), do: :ok
  end

  test "Exec startup faults preserve the committed state", %{jido: jido} do
    for {failure, reason} <- [
          {:raise, %RuntimeError{message: "Exec unavailable"}},
          {:throw, {:throw, :exec_unavailable}}
        ] do
      {:ok, server} =
        Jido.start_agent(jido, Agent, exec_module: FailedExec, exec_opts: [failure: failure])

      original = Server.snapshot(server)
      assert {:error, ^reason} = Server.call(server, signal("boundary.emit", %{count: 1}))
      assert Server.snapshot(server) == original
      assert Server.status(server).phase == :idle
    end
  end

  test "error Signal policy reports failure without causing a feedback loop", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent, error_policy: {:emit_signal, {:pid, target: self()}})

    original = Server.snapshot(server)
    assert {:error, _} = Server.call(server, signal("boundary.fail"))
    assert_receive {:signal, error_signal}
    assert error_signal.type == "jido.agent.error"
    assert error_signal.data.agent_id == original.agent.id
    assert error_signal.data.stage == :execute
    refute error_signal.data.committed?
    assert Server.snapshot(server) == original

    assert {:error, _} = Server.call(server, error_signal)
    refute_received {:signal, _}
    assert Server.snapshot(server) == original
  end

  test "invalid and raised policy results stop the Server with a structured reason", %{jido: jido} do
    for {policy, expected} <- [
          {fn _, _ -> :invalid end, {:invalid_error_policy_result, :invalid}},
          {fn _, _ -> raise "policy failed" end,
           {:error_policy_failed, %RuntimeError{message: "policy failed"}}}
        ] do
      {:ok, server} = Jido.start_agent(jido, Agent, error_policy: policy, restart: :temporary)
      ref = Process.monitor(server)
      assert {:error, _} = Server.call(server, signal("boundary.fail"))
      assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, ^expected}}
    end
  end

  test "Directive count limits reject the candidate before commit", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent, max_directives_per_turn: 1, directive_timeout: :infinity)

    original = Server.snapshot(server)

    assert {:error, {:too_many_directives, %{count: 2, limit: 1}}} =
             Server.call(server, signal("boundary.emit", %{count: 2}))

    assert Server.snapshot(server) == original
    assert {:ok, committed} = Server.call(server, signal("boundary.emit", %{count: 1}))
    eventually(fn -> Server.status(server).phase == :idle end)
    assert committed.state.count == 1
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
  end

  test "named Servers support liveness checks and remove names on stop", %{jido: jido} do
    for name <- [
          {:global, {__MODULE__, jido}},
          Server.via_tuple("named-boundary", Jido.registry_name(jido)),
          Module.concat(jido, BoundaryAgent)
        ] do
      server = start_supervised!({Server, agent: Agent, name: name})
      assert Server.alive?(server)
      assert Server.alive?(name)
      assert :ok = Server.await_ready(name)
      assert :ok = Server.stop(server)
      refute Server.alive?(server)
      refute Server.alive?(name)
      assert {:error, :not_running} = Server.await_ready(server)
    end
  end

  test "idle cancellation and invalid control requests keep the Agent usable", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Agent, debug: true)
    original = Server.snapshot(server)
    assert {:error, :idle} = Server.cancel(server)
    assert {:error, :unknown_call} = :gen_statem.call(server, :unsupported)
    :gen_statem.cast(server, :unsupported)
    assert {:ok, []} = Server.recent_events(server, limit: :invalid)

    assert {:error, {:adopt_child_failed, :child_not_found}} =
             Server.adopt_child(server, "missing", :child)

    parent = ParentRef.new!(pid: server, id: original.agent.id, tag: :self)
    assert {:error, :cannot_adopt_self} = Server.adopt_parent(server, parent)
    assert Server.snapshot(server) == original
  end

  test "startup rejects invalid Exec options, limits, names and missing persistence", %{
    jido: jido
  } do
    for opts <- [
          [exec_module: String],
          [exec_opts: :invalid],
          [exec_opts: [:invalid]],
          [max_postponed_signals: -1],
          [max_directives_per_turn: -1]
        ] do
      assert {:error, _} = Jido.start_agent(jido, Agent, opts)
    end

    assert {:error, :jido_instance_required} = Server.start(agent: Agent)
    assert {:error, _} = Jido.start_agent(jido, Agent, persistence: nil, restore: :required)
    assert_raise ArgumentError, fn -> Server.start_link(agent: Agent, name: 123) end
  end
end
