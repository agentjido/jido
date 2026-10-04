defmodule JidoTest.Examples.Research.ChildTopologyValidationTest do
  use ExUnit.Case, async: true
  @moduletag :example

  alias Jido.Examples.Research.ChildTopologyRuntime.{CycleA, Specifications}
  alias Jido.Topology
  alias Jido.Topology.Codec

  for child_form <- [:dsl, :data, :data_agents] do
    test "Topology JSON retains the #{child_form} child definition and gate" do
      assert {:ok, definition} = Specifications.parent(:data, unquote(child_form))
      assert {:ok, document, registry} = Codec.encode(definition)
      assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
      assert {:error, %Jido.Error.ValidationError{}} = Codec.decode(document, %{})
    end
  end

  test "a module child cycle is rejected during definition validation" do
    assert {:error, %Jido.Error.ValidationError{} = error} =
             Topology.new(
               name: "cycle-root",
               children: [%{key: :team, topology: CycleA, gate: %{commands: [], events: []}}]
             )

    assert String.downcase(error.message) =~ "cycle"
  end

  test "duplicate child gate identities are rejected" do
    assert {:ok, child} = Specifications.child_entry(:dsl)

    assert {:error, %Jido.Error.ValidationError{} = error} =
             Topology.new(name: "duplicate-gates", children: [child, child])

    assert String.downcase(error.message) =~ "duplicate"
  end

  test "an accepted command must name a declared child member" do
    assert {:ok, child} = Specifications.child_entry(:dsl)
    bad_gate = %{child.gate | commands: [%{type: Specifications.command(), member: :missing}]}

    assert {:error, %Jido.Error.ValidationError{} = error} =
             Topology.new(name: "invalid-gate", children: [%{child | gate: bad_gate}])

    assert error.message =~ "member"
  end
end

defmodule JidoTest.Examples.Research.ChildTopologyScopeTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.ChildTopologyRuntimeAssertions

  alias Jido.AgentServer
  alias Jido.Examples.Research.ChildTopologyRuntime.Specifications

  test "the same child key has a separate identity and state under each parent", c do
    assert {:ok, definition} = Specifications.parent(:dsl, :dsl)
    first_id = unique_id("first-parent")
    second_id = unique_id("second-parent")
    first = start_supervised!({runtime(), opts(c.jido, first_id, definition)})
    second = start_supervised!({runtime(), opts(c.jido, second_id, definition)})

    try do
      assert {:ok, _} = call_child(c.jido, first_id, 5)
      assert {:ok, _} = call_child(c.jido, second_id, 2)
      a = rpc(:whereis_member, [c.jido, child_id(first_id), :alice])
      b = rpc(:whereis_member, [c.jido, child_id(second_id), :alice])
      assert a != b
      assert AgentServer.agent(a).state.total == 5
      assert AgentServer.agent(b).state.total == 2
      assert AgentServer.agent(a).id != AgentServer.agent(b).id
    after
      stop_runtime(c.jido, first_id, first, 3)
      assert Process.alive?(second)
      stop_runtime(c.jido, second_id, second)
    end
  end

  test "the runtime rejects excessive nesting before any process starts", c do
    assert {:error, %Jido.Error.ValidationError{} = error} =
             rpc(:start_link, [
               opts(c.jido, unique_id("depth"), Specifications.nested(4), max_depth: 2)
             ])

    assert String.downcase(error.message) =~ "depth"
    assert Jido.agent_count(c.jido) == 0
  end

  test "a declared gate can call a grandchild without flattening either runtime", c do
    assert {:ok, definition} = Specifications.nested_parent()
    id = unique_id("nested-parent")
    parent = start_supervised!({runtime(), opts(c.jido, id, definition, max_depth: 4)})

    try do
      assert {:ok, %{state: %{total: 5}}} = call_child(c.jido, id, 5)
      middle = child_id(id)
      leaf = child_id(middle)
      assert is_pid(rpc(:whereis_runtime, [c.jido, middle]))
      assert is_pid(rpc(:whereis_runtime, [c.jido, leaf]))
      assert is_pid(rpc(:whereis_member, [c.jido, leaf, :alice]))
      assert rpc(:whereis_member, [c.jido, id, :alice]) == nil
      assert rpc(:whereis_member, [c.jido, middle, :alice]) == nil
      assert rpc(:whereis_member, [c.jido, leaf, :bob]) == nil
    after
      stop_runtime(c.jido, id, parent)
    end
  end
end
