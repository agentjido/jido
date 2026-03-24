defmodule JidoTest.Agent.StateOpsTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.StateOp
  alias Jido.Agent.StateOps
  alias Jido.Thread

  describe "apply_result/2" do
    test "merges result into agent state" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{existing: "value"}})
      updated = StateOps.apply_result(agent, %{new: "data"})

      assert updated.state.existing == "value"
      assert updated.state.new == "data"
    end

    test "deep merges nested maps" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{config: %{a: 1, b: 2}}})
      updated = StateOps.apply_result(agent, %{config: %{b: 3, c: 4}})

      assert updated.state.config == %{a: 1, b: 3, c: 4}
    end

    test "overwrites non-map values" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{value: 1}})
      updated = StateOps.apply_result(agent, %{value: 2})

      assert updated.state.value == 2
    end
  end

  describe "apply_state_ops/2 with SetState" do
    test "merges attributes into state" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{existing: "value"}})

      {updated, directives} =
        StateOps.apply_state_ops(agent, [%StateOp.SetState{attrs: %{new: "data"}}])

      assert updated.state.existing == "value"
      assert updated.state.new == "data"
      assert directives == []
    end

    test "deep merges nested SetState" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{config: %{a: 1}}})

      {updated, _} =
        StateOps.apply_state_ops(agent, [%StateOp.SetState{attrs: %{config: %{b: 2}}}])

      assert updated.state.config == %{a: 1, b: 2}
    end
  end

  describe "apply_state_ops/2 with ReplaceState" do
    test "replaces state wholesale" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{old: "data", to_remove: true}})

      {updated, directives} =
        StateOps.apply_state_ops(agent, [%StateOp.ReplaceState{state: %{fresh: "state"}}])

      assert updated.state == %{fresh: "state"}
      refute Map.has_key?(updated.state, :old)
      assert directives == []
    end
  end

  describe "apply_state_ops/2 with DeleteKeys" do
    test "removes top-level keys" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{keep: 1, remove: 2, also_remove: 3}})

      {updated, directives} =
        StateOps.apply_state_ops(agent, [%StateOp.DeleteKeys{keys: [:remove, :also_remove]}])

      assert updated.state.keep == 1
      refute Map.has_key?(updated.state, :remove)
      refute Map.has_key?(updated.state, :also_remove)
      assert directives == []
    end

    test "handles non-existent keys gracefully" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{keep: 1}})

      {updated, _} =
        StateOps.apply_state_ops(agent, [%StateOp.DeleteKeys{keys: [:not_here]}])

      assert updated.state.keep == 1
    end
  end

  describe "apply_state_ops/2 with SetPath" do
    test "sets value at nested path" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{existing: "value"}})

      {updated, directives} =
        StateOps.apply_state_ops(agent, [
          %StateOp.SetPath{path: [:nested, :deep, :value], value: 42}
        ])

      assert updated.state.nested.deep.value == 42
      assert updated.state.existing == "value"
      assert directives == []
    end

    test "creates intermediate maps" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{}})

      {updated, _} =
        StateOps.apply_state_ops(agent, [%StateOp.SetPath{path: [:a, :b, :c], value: "deep"}])

      assert updated.state.a.b.c == "deep"
    end

    test "overwrites existing nested values" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{nested: %{value: "old"}}})

      {updated, _} =
        StateOps.apply_state_ops(agent, [%StateOp.SetPath{path: [:nested, :value], value: "new"}])

      assert updated.state.nested.value == "new"
    end

    test "handles single-element path" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{}})

      {updated, _} =
        StateOps.apply_state_ops(agent, [%StateOp.SetPath{path: [:key], value: "value"}])

      assert updated.state.key == "value"
    end
  end

  describe "apply_state_ops/2 with DeletePath" do
    test "deletes value at nested path" do
      {:ok, agent} =
        Agent.new(%{id: "test", state: %{nested: %{to_remove: "gone", keep: "here"}}})

      {updated, directives} =
        StateOps.apply_state_ops(agent, [%StateOp.DeletePath{path: [:nested, :to_remove]}])

      refute Map.has_key?(updated.state.nested, :to_remove)
      assert updated.state.nested.keep == "here"
      assert directives == []
    end

    test "handles non-existent path gracefully" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{keep: 1}})

      {updated, _} =
        StateOps.apply_state_ops(agent, [%StateOp.DeletePath{path: [:not, :here]}])

      assert updated.state.keep == 1
    end
  end

  describe "apply_state_ops/2 with AppendThread" do
    test "initializes a thread when missing and appends entries" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{}})

      {updated, directives} =
        StateOps.apply_state_ops(agent, [
          %StateOp.AppendThread{entries: [%{kind: :message, payload: %{text: "hello"}}]}
        ])

      assert directives == []
      assert %Thread{} = updated.state.__thread__
      assert Thread.entry_count(updated.state.__thread__) == 1
      assert Thread.last(updated.state.__thread__).payload == %{text: "hello"}
    end

    test "appends to an existing thread" do
      {:ok, agent} =
        Agent.new(%{
          id: "test",
          state: %{__thread__: Thread.new() |> Thread.append(%{kind: :note, payload: %{n: 1}})}
        })

      {updated, directives} =
        StateOps.apply_state_ops(agent, [
          %StateOp.AppendThread{entries: [%{kind: :note, payload: %{n: 2}}]}
        ])

      assert directives == []
      assert Thread.entry_count(updated.state.__thread__) == 2
      assert Thread.last(updated.state.__thread__).payload == %{n: 2}
    end

    test "treats empty batches as a no-op" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{}})

      {updated, directives} =
        StateOps.apply_state_ops(agent, [%StateOp.AppendThread{entries: []}])

      assert directives == []
      refute Map.has_key?(updated.state, :__thread__)
    end
  end

  describe "apply_state_ops/2 with external directives" do
    test "passes through external directives unchanged" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{}})

      emit = %Directive.Emit{signal: %{type: "test"}}
      schedule = %Directive.Schedule{delay_ms: 1000, message: :tick}

      {_updated, directives} = StateOps.apply_state_ops(agent, [emit, schedule])

      assert directives == [emit, schedule]
    end

    test "preserves order of directives" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{}})

      d1 = %Directive.Emit{signal: %{type: "first"}}
      d2 = %Directive.Emit{signal: %{type: "second"}}
      d3 = %Directive.Emit{signal: %{type: "third"}}

      {_, directives} = StateOps.apply_state_ops(agent, [d1, d2, d3])

      assert directives == [d1, d2, d3]
    end
  end

  describe "apply_state_ops/2 with mixed effects" do
    test "applies internal effects and collects external directives" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{initial: true}})

      effects = [
        %StateOp.SetState{attrs: %{added: "by_set_state"}},
        %Directive.Emit{signal: %{type: "event.1"}},
        %StateOp.SetPath{path: [:nested, :value], value: 123},
        %Directive.Schedule{delay_ms: 5000, message: :timeout}
      ]

      {updated, directives} = StateOps.apply_state_ops(agent, effects)

      assert updated.state.initial == true
      assert updated.state.added == "by_set_state"
      assert updated.state.nested.value == 123

      assert length(directives) == 2
      assert Enum.any?(directives, &match?(%Directive.Emit{}, &1))
      assert Enum.any?(directives, &match?(%Directive.Schedule{}, &1))
    end

    test "applies effects in order" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{counter: 0}})

      effects = [
        %StateOp.SetState{attrs: %{counter: 1}},
        %StateOp.SetState{attrs: %{counter: 2}},
        %StateOp.SetState{attrs: %{counter: 3}}
      ]

      {updated, _} = StateOps.apply_state_ops(agent, effects)

      assert updated.state.counter == 3
    end
  end

  describe "deep_put_in/3" do
    test "sets value at single-level path" do
      result = StateOps.deep_put_in(%{}, [:key], "value")
      assert result == %{key: "value"}
    end

    test "sets value at multi-level path" do
      result = StateOps.deep_put_in(%{}, [:a, :b, :c], "deep")
      assert result == %{a: %{b: %{c: "deep"}}}
    end

    test "preserves existing values" do
      map = %{a: %{existing: true}}
      result = StateOps.deep_put_in(map, [:a, :new], "value")
      assert result == %{a: %{existing: true, new: "value"}}
    end

    test "overwrites existing nested values" do
      map = %{a: %{b: "old"}}
      result = StateOps.deep_put_in(map, [:a, :b], "new")
      assert result == %{a: %{b: "new"}}
    end
  end
end
