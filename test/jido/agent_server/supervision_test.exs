defmodule Jido.AgentServer.SupervisionTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias JidoTest.SupervisedCounter, as: Counter

  test "a child specification fixes generated identity across OTP restarts", c do
    spec = Server.child_spec(jido: c.jido, agent: Counter)
    {{Server, id}, {Server, :start_link, [opts]}} = {spec.id, spec.start}
    assert opts[:id] == id
    assert spec.restart == :transient
    server = start_supervised!(spec)
    assert :ok = Server.await_ready(server)
    {:ok, signal} = Counter.increment_signal(%{})
    assert {:ok, committed} = Server.call(server, signal)
    kill(server)
    eventually(fn -> is_pid(Jido.whereis_agent(c.jido, id)) end)
    replacement = Jido.whereis_agent(c.jido, id)
    assert replacement != server
    assert Server.agent(replacement) == committed
    assert Server.snapshot(replacement).state_version == 1
  end

  test "an instantiated Agent supplies its own stable child ID", c do
    agent = Counter.new!(id: "instance-child")
    spec = Server.child_spec(jido: c.jido, agent: agent)
    assert spec.id == {Server, agent.id}
    server = start_supervised!(spec)
    assert :ok = Server.await_ready(server)
    kill(server)
    eventually(fn -> is_pid(Jido.whereis_agent(c.jido, agent.id)) end)
    assert Server.agent(Jido.whereis_agent(c.jido, agent.id)).id == agent.id
  end

  for storage <- [:runtime, :durable] do
    test "current definition replaces saved runtime configuration with #{storage} recovery", c do
      opts =
        if unquote(storage) == :durable,
          do: [persistence: {Jido.Persistence.ETS, table: :"restore_#{c.jido}"}],
          else: []

      jido = :"current_#{c.jido}"
      start_supervised!({Jido, [name: jido, namespace: Atom.to_string(jido)] ++ opts})

      old =
        Jido.Agent.new!(%{
          Counter.definition()
          | vsn: nil,
            metadata: %{label: "old"},
            plugins: [{Counter.Runtime, label: "old"}]
        })

      server =
        start_supervised!({Server, jido: jido, agent: old, id: "current", restart: :temporary})

      assert :ok = Server.await_ready(server)
      {:ok, signal} = Counter.increment_signal(%{})
      assert {:ok, committed} = Server.call(server, signal)
      kill(server)

      replacement =
        start_supervised!(
          {Server, jido: jido, agent: Counter, id: "current", restore_definition: :current},
          id: :replacement
        )

      assert :ok = Server.await_ready(replacement)
      assert Server.agent(replacement).state == committed.state
      assert Server.agent(replacement).metadata == Counter.definition().metadata
      assert Server.snapshot(replacement).state_version == 1
      runtime = Server.children(replacement)[{:plugin, Counter.Runtime}].pid
      init = Elixir.Agent.get(runtime, & &1)
      assert init.options == [label: "current"]
      assert init.state_version == 1
    end
  end

  test "current definition rejects saved state that does not pass its schema", c do
    Process.flag(:trap_exit, true)

    server =
      start_supervised!({Server, jido: c.jido, agent: Counter, id: "schema", restart: :temporary})

    {:ok, signal} = Counter.increment_signal(%{})
    assert {:ok, _} = Server.call(server, signal)
    kill(server)

    definition =
      Jido.Agent.new!(%{
        Counter.definition()
        | vsn: nil,
          schema: Zoi.object(%{count: Zoi.integer() |> Zoi.min(2) |> Zoi.default(2)})
      })

    assert {:error, %Jido.Error.ValidationError{}} =
             Server.start_link(
               jido: c.jido,
               agent: definition,
               id: "schema",
               restore_definition: :current
             )
  end

  test "invalid restore definition option returns a structured error", c do
    assert {:error, %Jido.Error.ValidationError{}} =
             Server.start_link(jido: c.jido, agent: Counter, restore_definition: :invalid)
  end

  defp kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1_000
  end
end
