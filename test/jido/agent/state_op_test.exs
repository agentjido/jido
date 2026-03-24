defmodule JidoTest.Agent.StateOpTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.StateOp

  describe "set_state/1" do
    test "creates SetState state operation" do
      effect = StateOp.set_state(%{status: :running})
      assert %StateOp.SetState{attrs: %{status: :running}} = effect
    end

    test "requires a map" do
      effect = StateOp.set_state(%{a: 1, b: 2})
      assert effect.attrs == %{a: 1, b: 2}
    end
  end

  describe "replace_state/1" do
    test "creates ReplaceState state operation" do
      effect = StateOp.replace_state(%{new: :state})
      assert %StateOp.ReplaceState{state: %{new: :state}} = effect
    end

    test "stores the complete new state" do
      new_state = %{completely: "new", data: 123}
      effect = StateOp.replace_state(new_state)
      assert effect.state == new_state
    end
  end

  describe "delete_keys/1" do
    test "creates DeleteKeys state operation" do
      effect = StateOp.delete_keys([:temp, :cache])
      assert %StateOp.DeleteKeys{keys: [:temp, :cache]} = effect
    end

    test "accepts empty list" do
      effect = StateOp.delete_keys([])
      assert effect.keys == []
    end

    test "accepts single key" do
      effect = StateOp.delete_keys([:single])
      assert effect.keys == [:single]
    end
  end

  describe "set_path/2" do
    test "creates SetPath state operation" do
      effect = StateOp.set_path([:config, :timeout], 5000)
      assert %StateOp.SetPath{path: [:config, :timeout], value: 5000} = effect
    end

    test "accepts single-element path" do
      effect = StateOp.set_path([:key], "value")
      assert effect.path == [:key]
      assert effect.value == "value"
    end

    test "accepts deep paths" do
      effect = StateOp.set_path([:a, :b, :c, :d], :deep_value)
      assert effect.path == [:a, :b, :c, :d]
    end

    test "accepts any value type" do
      effect = StateOp.set_path([:data], %{nested: [1, 2, 3]})
      assert effect.value == %{nested: [1, 2, 3]}
    end
  end

  describe "delete_path/1" do
    test "creates DeletePath state operation" do
      effect = StateOp.delete_path([:temp, :cache])
      assert %StateOp.DeletePath{path: [:temp, :cache]} = effect
    end

    test "accepts single-element path" do
      effect = StateOp.delete_path([:key])
      assert effect.path == [:key]
    end

    test "accepts deep paths" do
      effect = StateOp.delete_path([:a, :b, :c])
      assert effect.path == [:a, :b, :c]
    end
  end

  describe "append_thread/1" do
    test "wraps a single entry" do
      effect = StateOp.append_thread(%{kind: :message, payload: %{text: "hi"}})

      assert %StateOp.AppendThread{
               entries: [%{kind: :message, payload: %{text: "hi"}}]
             } = effect
    end

    test "preserves entry batches" do
      entries = [
        %{kind: :note, payload: %{text: "one"}},
        %{kind: :note, payload: %{text: "two"}}
      ]

      effect = StateOp.append_thread(entries)
      assert effect.entries == entries
    end
  end

  describe "state op structs" do
    test "SetState struct fields" do
      effect = %StateOp.SetState{attrs: %{a: 1}}
      assert effect.attrs == %{a: 1}
    end

    test "ReplaceState struct fields" do
      effect = %StateOp.ReplaceState{state: %{b: 2}}
      assert effect.state == %{b: 2}
    end

    test "DeleteKeys struct fields" do
      effect = %StateOp.DeleteKeys{keys: [:x, :y]}
      assert effect.keys == [:x, :y]
    end

    test "SetPath struct fields" do
      effect = %StateOp.SetPath{path: [:p], value: :v}
      assert effect.path == [:p]
      assert effect.value == :v
    end

    test "DeletePath struct fields" do
      effect = %StateOp.DeletePath{path: [:q, :r]}
      assert effect.path == [:q, :r]
    end

    test "AppendThread struct fields" do
      effect = %StateOp.AppendThread{entries: [%{kind: :message}]}
      assert effect.entries == [%{kind: :message}]
    end
  end

  describe "schema functions" do
    test "SetState.schema/0 returns Zoi schema" do
      assert %{__struct__: Zoi.Types.Struct, module: StateOp.SetState} =
               StateOp.SetState.schema()
    end

    test "ReplaceState.schema/0 returns Zoi schema" do
      assert %{__struct__: Zoi.Types.Struct, module: StateOp.ReplaceState} =
               StateOp.ReplaceState.schema()
    end

    test "DeleteKeys.schema/0 returns Zoi schema" do
      assert %{__struct__: Zoi.Types.Struct, module: StateOp.DeleteKeys} =
               StateOp.DeleteKeys.schema()
    end

    test "SetPath.schema/0 returns Zoi schema" do
      assert %{__struct__: Zoi.Types.Struct, module: StateOp.SetPath} =
               StateOp.SetPath.schema()
    end

    test "DeletePath.schema/0 returns Zoi schema" do
      assert %{__struct__: Zoi.Types.Struct, module: StateOp.DeletePath} =
               StateOp.DeletePath.schema()
    end

    test "AppendThread.schema/0 returns Zoi schema" do
      assert %{__struct__: Zoi.Types.Struct, module: StateOp.AppendThread} =
               StateOp.AppendThread.schema()
    end
  end
end
