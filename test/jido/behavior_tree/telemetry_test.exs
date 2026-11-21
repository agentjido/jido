defmodule Jido.BehaviorTree.TelemetryTest do
  use ExUnit.Case, async: false

  alias Jido.BehaviorTree.{Agent, Node, Tick, Tree}
  alias Jido.BehaviorTree.Test.Nodes.{ErrorNode, SimpleNode}

  test "events/0 exposes expected node telemetry events" do
    assert [:jido, :bt, :node, :tick, :start] in Jido.BehaviorTree.Telemetry.events()
    assert [:jido, :bt, :node, :tick, :stop] in Jido.BehaviorTree.Telemetry.events()
    assert [:jido, :bt, :node, :tick, :exception] in Jido.BehaviorTree.Telemetry.events()
  end

  test "metrics/0 returns telemetry metric definitions" do
    metrics = Jido.BehaviorTree.Telemetry.metrics()
    assert is_list(metrics)
    assert length(metrics) >= 1
  end

  test "child_spec/1 returns a valid worker spec" do
    child_spec = Jido.BehaviorTree.Telemetry.child_spec([])

    assert child_spec.id == Jido.BehaviorTree.Telemetry
    assert child_spec.type == :worker
    assert match?({Jido.BehaviorTree.Telemetry, :start_link, [[]]}, child_spec.start)
  end

  test "node tick emits start and stop telemetry with metadata" do
    handler_id = "bt-telemetry-start-stop-#{System.unique_integer([:positive])}"
    attach_handler(handler_id, [[:jido, :bt, :node, :tick, :start], [:jido, :bt, :node, :tick, :stop]])

    tick = Tick.new()
    _result = Node.execute_tick(SimpleNode.new("telemetry"), tick)

    assert_receive {:telemetry_event, [:jido, :bt, :node, :tick, :start], start_measurements, start_metadata}
    assert is_integer(start_measurements.system_time)
    assert start_metadata.node == SimpleNode
    assert start_metadata.sequence == 0

    assert_receive {:telemetry_event, [:jido, :bt, :node, :tick, :stop], stop_measurements, stop_metadata}
    assert is_integer(stop_measurements.duration)
    assert stop_metadata.node == SimpleNode
    assert stop_metadata.sequence == 0

    :telemetry.detach(handler_id)
  end

  test "agent ticks propagate increasing sequence metadata to node telemetry" do
    handler_id = "bt-telemetry-agent-seq-#{System.unique_integer([:positive])}"
    attach_handler(handler_id, [[:jido, :bt, :node, :tick, :stop]])

    tree = Tree.new(SimpleNode.new("agent sequence"))
    {:ok, agent} = Agent.start_link(tree: tree, mode: :manual)

    assert :success == Agent.tick(agent)
    assert :success == Agent.tick(agent)

    assert_receive {:telemetry_event, [:jido, :bt, :node, :tick, :stop], _m1, md1}
    assert_receive {:telemetry_event, [:jido, :bt, :node, :tick, :stop], _m2, md2}

    assert [md1.sequence, md2.sequence] == [0, 1]

    :telemetry.detach(handler_id)
    GenServer.stop(agent)
  end

  test "node tick emits stop event with error status for node errors" do
    handler_id = "bt-telemetry-error-#{System.unique_integer([:positive])}"
    attach_handler(handler_id, [[:jido, :bt, :node, :tick, :stop]])

    tick = Tick.new()
    _result = Node.execute_tick(ErrorNode.new("telemetry error"), tick)

    assert_receive {:telemetry_event, [:jido, :bt, :node, :tick, :stop], stop_measurements, stop_metadata}
    assert is_integer(stop_measurements.duration)
    assert match?({:error, _}, stop_metadata.status)
    assert stop_metadata.node == ErrorNode

    :telemetry.detach(handler_id)
  end

  test "handle_event/4 matches all supported telemetry patterns" do
    metadata = %{node: SimpleNode, sequence: 1}
    measurements = %{duration: 10, status: :success}

    Application.put_env(:jido, :behavior_tree_telemetry, log_level: false)

    Jido.BehaviorTree.Telemetry.handle_event([:jido, :bt, :node, :tick, :start], %{}, metadata, %{})
    Jido.BehaviorTree.Telemetry.handle_event([:jido, :bt, :node, :tick, :stop], measurements, metadata, %{})

    Jido.BehaviorTree.Telemetry.handle_event(
      [:jido, :bt, :node, :tick, :exception],
      %{duration: 10},
      Map.put(metadata, :error, :boom),
      %{}
    )

    Jido.BehaviorTree.Telemetry.handle_event([:jido, :bt, :node, :halt, :start], %{}, metadata, %{})
    Jido.BehaviorTree.Telemetry.handle_event([:jido, :bt, :node, :halt, :stop], %{duration: 10}, metadata, %{})

    Jido.BehaviorTree.Telemetry.handle_event(
      [:jido, :bt, :node, :halt, :exception],
      %{duration: 10},
      Map.put(metadata, :error, :boom),
      %{}
    )

    Application.delete_env(:jido, :behavior_tree_telemetry)
  end

  defp attach_handler(handler_id, events) do
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, metadata, pid ->
          send(pid, {:telemetry_event, event, measurements, metadata})
        end,
        test_pid
      )
  end
end
