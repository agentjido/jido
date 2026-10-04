defmodule Jido.Topology.ChildRuntimeTest do
  use JidoTest.Case, async: true

  alias Jido.{AgentServer, Signal, Topology}
  alias Jido.Signal.Bus
  alias Jido.Topology.Runtime
  alias JidoTest.AgentFixtures.CounterAgent

  defmodule Publisher do
    use Jido.Agent, name: "child_runtime_publisher"

    agent do
      schema Zoi.object(%{})
    end

    routes do
      route "child.publish" do
        action input, context: context do
          bus = Runtime.whereis_bus(input.jido, input.topology, :events)
          event = Signal.new!("child.done", %{}, source: "/test/child")

          with {:ok, [_]} <- Bus.publish(bus, [event]), do: {:ok, context.agent_state}
        end
      end
    end
  end

  defmodule FailReady do
    use Jido.Plugin

    @impl true
    def child_spec(_init),
      do: %{id: __MODULE__, start: {Elixir.Agent, :start_link, [fn -> :ready end]}}

    @impl true
    def await_ready(_runtime, _opts), do: {:error, :injected_readiness_failure}
  end

  defmodule Director do
    use Jido.Agent, name: "child_runtime_status_director"

    agent do
      schema Zoi.object(%{statuses: Zoi.list(Zoi.atom()) |> Zoi.default([])})
    end

    routes do
      route "jido.topology.lifecycle.child.status_changed" do
        action input, context: context do
          {:ok, %{statuses: context.agent_state.statuses ++ [input.status]}}
        end
      end
    end
  end

  test "the first command can publish an exported event", c do
    leaf = %{
      leaf()
      | agents: [%{key: :counter, module: Publisher}],
        connections: [%{agent: :counter, to: :events, path: "unused.command"}]
    }

    id = start_parent(c.jido, leaf, "child.publish")
    command = signal("child.publish", %{jido: c.jido, topology: child_id(id)})
    assert {:ok, _} = Runtime.call(c.jido, id, {:child, :team}, command)
    assert :ok = Runtime.await_gate_idle(c.jido, id, :team)
    assert length(exported(c.jido, id)) == 1
  end

  test "a Bus activated after its child member exports its first event", c do
    id = start_parent(c.jido, leaf())
    assert {:ok, _} = Runtime.call(c.jido, id, {:child, :team}, add())
    assert Runtime.whereis_bus(c.jido, child_id(id), :events) == nil
    assert {:ok, [_]} = Runtime.publish(c.jido, child_id(id), :events, [event()])
    assert :ok = Runtime.await_gate_idle(c.jido, id, :team)
    assert length(exported(c.jido, id)) == 1
  end

  test "a replacement Bus exports direct publication before another child command", c do
    id = start_parent(c.jido, leaf())
    assert {:ok, _} = Runtime.call(c.jido, id, {:child, :team}, add())
    assert {:ok, [_]} = Runtime.publish(c.jido, child_id(id), :events, [event()])
    assert :ok = Runtime.await_gate_idle(c.jido, id, :team)
    original = Runtime.whereis_bus(c.jido, child_id(id), :events)
    kill(original)

    eventually(fn ->
      replacement = Runtime.whereis_bus(c.jido, child_id(id), :events)
      is_pid(replacement) and replacement != original
    end)

    replacement = Runtime.whereis_bus(c.jido, child_id(id), :events)
    assert {:ok, [_]} = Bus.publish(replacement, [event()])
    assert :ok = Runtime.await_gate_idle(c.jido, id, :team)
    assert length(exported(c.jido, id)) == 2
  end

  test "gate recovery attaches once to a Bus that stays alive", c do
    id = start_parent(c.jido, leaf())
    assert {:ok, _} = Runtime.call(c.jido, id, {:child, :team}, add())
    assert {:ok, [_]} = Runtime.publish(c.jido, child_id(id), :events, [event()])
    assert :ok = Runtime.await_gate_idle(c.jido, id, :team)
    bus = Runtime.whereis_bus(c.jido, child_id(id), :events)
    gate = Runtime.lookup(c.jido, id, {:gate, "team"})
    kill(gate)

    eventually(fn ->
      replacement = Runtime.lookup(c.jido, id, {:gate, "team"})
      is_pid(replacement) and replacement != gate
    end)

    assert :ok = Runtime.await_gate_idle(c.jido, id, :team)
    assert Runtime.whereis_bus(c.jido, child_id(id), :events) == bus
    assert {:ok, [_]} = Bus.publish(bus, [event()])
    assert :ok = Runtime.await_gate_idle(c.jido, id, :team)
    assert length(exported(c.jido, id)) == 2
  end

  test "a child that never becomes ready does not emit a ready event", c do
    failing = %{CounterAgent.definition() | name: "failing", plugins: [FailReady]}

    target =
      Topology.new!(
        name: "parent",
        children: [
          %{
            key: :team,
            topology: %{
              name: "leaf",
              startup: %{retry_interval: 10_000},
              agents: [%{key: :counter, definition: failing}]
            },
            activation: :eager
          }
        ]
      )

    id = unique_id("child_status")

    start_supervised!(
      {Runtime,
       jido: c.jido, id: id, topology: target, director: Director.definition(), activation: :lazy}
    )

    eventually(fn -> is_pid(Runtime.whereis_child(c.jido, id, :team)) end)
    assert {:error, :activation_timeout} = Runtime.await_ready(c.jido, child_id(id), 100)
    assert :ok = Runtime.await_gate_idle(c.jido, id, :team)
    director = Runtime.director(c.jido, id)
    eventually(fn -> :degraded in AgentServer.agent(director).state.statuses end)
    refute :ready in AgentServer.agent(director).state.statuses
  end

  defp leaf do
    %{
      name: "leaf",
      agents: [%{key: :counter, module: CounterAgent}],
      resources: [%{key: :events, kind: :bus}],
      connections: []
    }
  end

  defp start_parent(jido, leaf, command \\ "counter.add") do
    target =
      Topology.new!(
        name: "parent",
        resources: [%{key: :events, kind: :bus}],
        children: [
          %{
            key: :team,
            topology: leaf,
            activation: :lazy,
            gate: %{
              commands: [%{type: command, member: :counter}],
              events: ["child.done"],
              to: :events
            }
          }
        ]
      )

    id = unique_id("child_events")
    start_supervised!({Runtime, jido: jido, id: id, topology: target, activation: :lazy})
    assert {:ok, []} = Runtime.publish(jido, id, :events, [])
    id
  end

  defp child_id(id), do: id <> "/child/team"
  defp add, do: signal("counter.add", %{by: 1, label: "child"})
  defp event, do: signal("child.done", %{})

  defp exported(jido, id) do
    assert {:ok, records} = Bus.replay(Runtime.whereis_bus(jido, id, :events), "child.done")
    records
  end

  defp kill(pid) do
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5_000
  end
end
