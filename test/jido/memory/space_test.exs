defmodule JidoTest.Memory.SpaceTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Space

  describe "new/1" do
    test "creates space with default values" do
      space = Space.new(%{})
      assert space.data == %{}
      assert space.rev == 0
      assert space.metadata == %{}
    end

    test "creates space from keyword list" do
      space = Space.new(data: [1, 2, 3], metadata: %{type: :evidence})
      assert space.data == [1, 2, 3]
      assert space.metadata == %{type: :evidence}
    end

    test "creates space with custom data" do
      space = Space.new(%{data: %{key: "value"}, rev: 5})
      assert space.data == %{key: "value"}
      assert space.rev == 5
    end
  end

  describe "new_kv/0,1" do
    test "creates map space with empty data" do
      space = Space.new_kv()
      assert space.data == %{}
      assert space.rev == 0
      assert Space.map?(space)
    end

    test "creates map space with initial data" do
      space = Space.new_kv(data: %{temperature: 22})
      assert space.data == %{temperature: 22}
    end

    test "creates map space with metadata" do
      space = Space.new_kv(metadata: %{source: :sensor})
      assert space.metadata == %{source: :sensor}
    end
  end

  describe "new_list/0,1" do
    test "creates list space with empty data" do
      space = Space.new_list()
      assert space.data == []
      assert space.rev == 0
      assert Space.list?(space)
    end

    test "creates list space with initial data" do
      space = Space.new_list(data: [%{id: "t1", text: "task"}])
      assert space.data == [%{id: "t1", text: "task"}]
    end

    test "creates list space with metadata" do
      space = Space.new_list(metadata: %{priority: :high})
      assert space.metadata == %{priority: :high}
    end
  end

  describe "map?/1" do
    test "returns true for map space" do
      assert Space.map?(Space.new_kv()) == true
    end

    test "returns false for list space" do
      assert Space.map?(Space.new_list()) == false
    end
  end

  describe "list?/1" do
    test "returns true for list space" do
      assert Space.list?(Space.new_list()) == true
    end

    test "returns false for map space" do
      assert Space.list?(Space.new_kv()) == false
    end
  end

  describe "schema/0" do
    test "returns Zoi schema" do
      schema = Space.schema()
      assert %Zoi.Types.Struct{module: Jido.Memory.Space} = schema
    end
  end
end
