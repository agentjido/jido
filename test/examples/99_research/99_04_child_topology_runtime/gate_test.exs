defmodule JidoTest.Examples.Research.ChildTopologyGateTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.ChildTopologyRuntimeAssertions

  alias Jido.AgentServer
  alias Jido.Examples.Research.ChildTopologyRuntime.Specifications
  alias Jido.Signal.Bus

  test "concurrent first commands use one child runtime and one member", c do
    assert {:ok, definition} = Specifications.parent(:dsl, :dsl)
    id = unique_id("coalesced-child")
    parent = start_supervised!({runtime(), opts(c.jido, id, definition)})

    try do
      assert :ok = rpc(:await_ready, [c.jido, id, 5_000])
      caller = self()

      tasks =
        for _ <- 1..12 do
          Task.async(fn ->
            send(caller, {:ready, self()})

            receive do
              :go -> call_child(c.jido, id)
            after
              5_000 -> flunk("concurrent caller was not released")
            end
          end)
        end

      for task <- tasks, do: assert_receive({:ready, pid} when pid == task.pid, 5_000)
      for task <- tasks, do: send(task.pid, :go)
      results = Enum.map(tasks, &Task.await(&1, 5_000))
      assert Enum.all?(results, &match?({:ok, %Jido.Agent{}}, &1))
      alice = rpc(:whereis_member, [c.jido, child_id(id), :alice])
      assert AgentServer.agent(alice).state.total == 12
      assert %{active_members: 1, dormant_members: 1} = rpc(:status, [c.jido, child_id(id)])
      assert Jido.agent_count(c.jido) == 3
      assert {:ok, %{state: %{total: 13}}} = call_child(c.jido, id)
      assert rpc(:whereis_member, [c.jido, child_id(id), :alice]) == alice
    after
      stop_runtime(c.jido, id, parent)
    end
  end

  test "a rejected command does not start the child", c do
    assert {:ok, definition} = Specifications.parent(:data, :dsl)
    id = unique_id("command-gate")
    parent = start_supervised!({runtime(), opts(c.jido, id, definition)})

    try do
      assert :ok = rpc(:await_ready, [c.jido, id, 5_000])
      rejected = signal("examples.research.child_runtime.private.command")

      assert {:error, :command_not_allowed} =
               rpc(:call, [c.jido, id, {:child, :team}, rejected, []])

      assert rpc(:whereis_child, [c.jido, id, :team]) == nil
      assert Jido.agent_count(c.jido) == 1
      assert {:ok, %{state: %{total: 1}}} = call_child(c.jido, id)
    after
      stop_runtime(c.jido, id, parent)
    end
  end

  for exports <- [[], ["examples.research.child_runtime.completed"]] do
    test "the gate exports only declared events #{inspect(exports)}", c do
      assert {:ok, definition} = Specifications.parent(:dsl, :dsl, events: unquote(exports))
      id = unique_id("event-gate")
      parent = start_supervised!({runtime(), opts(c.jido, id, definition)})

      try do
        assert :ok = rpc(:await_ready, [c.jido, id, 5_000])
        assert {:ok, _} = call_child(c.jido, id)
        probe = signal("examples.research.child_runtime.parent.probe")
        assert {:ok, [_]} = rpc(:publish, [c.jido, id, :signals, [probe], []])
        parent_bus = rpc(:whereis_bus, [c.jido, id, :signals])
        child_bus = rpc(:whereis_bus, [c.jido, child_id(id), :signals])
        assert is_pid(parent_bus)
        assert is_pid(child_bus)
        assert parent_bus != child_bus
        private = signal(Specifications.private_event(), %{value: 9})
        exported = signal(Specifications.exported_event(), %{value: 1})

        assert {:ok, [_, _]} =
                 rpc(:publish, [c.jido, child_id(id), :signals, [private, exported], []])

        # Gate drain is a public completion barrier for queued event forwarding.
        assert :ok = rpc(:await_gate_idle, [c.jido, id, :team, 5_000])
        assert {:ok, []} = Bus.replay(parent_bus, Specifications.private_event())
        assert {:ok, []} = Bus.replay(child_bus, probe.type)
        assert {:ok, parent_records} = Bus.replay(parent_bus, Specifications.exported_event())
        assert length(parent_records) == length(unquote(exports))
        assert rpc(:whereis_member, [c.jido, child_id(id), :bob]) == nil
      after
        stop_runtime(c.jido, id, parent)
      end
    end
  end

  test "Bus publication delivers to active subscribers and leaves Bob dormant", c do
    assert {:ok, definition} = Specifications.parent(:data, :dsl)
    id = unique_id("dormant-bus")
    parent = start_supervised!({runtime(), opts(c.jido, id, definition)})

    try do
      assert {:ok, _} = call_child(c.jido, id)
      child = child_id(id)
      assert {:ok, [_]} = rpc(:publish, [c.jido, child, :signals, [record()], []])
      alice = rpc(:whereis_member, [c.jido, child, :alice])
      eventually(fn -> AgentServer.agent(alice).state.total == 2 end)
      assert rpc(:whereis_member, [c.jido, child, :bob]) == nil
    after
      stop_runtime(c.jido, id, parent)
    end
  end
end
