defmodule Jido.Topology.ChildTest do
  use ExUnit.Case, async: true
  alias Jido.{Agent, Topology}
  alias Jido.Topology.Codec
  alias JidoTest.AgentFixtures.CounterAgent

  defmodule ConfigOnly do
    def __topology_config__, do: %{name: "config_only"}
  end

  defmodule RaisedConfig do
    def __topology_config__, do: raise(ArgumentError, "configuration failed")
  end

  defmodule ThrownConfig do
    def __topology_config__, do: throw(:configuration_failed)
  end

  defmodule ExitedConfig do
    def __topology_config__, do: exit(:configuration_failed)
  end

  defmodule InvalidConfig do
    def __topology_config__, do: nil
  end

  defmodule RaisedTopology do
    def topology, do: raise(ArgumentError, "configuration failed")
  end

  defmodule RaisedOwnerFlag do
    def __topology_config__, do: %{name: "child"}
    def __topology_owner__?, do: raise(ArgumentError, "configuration failed")
  end

  defmodule RaisedOwner do
    def __topology_config__, do: %{name: "child"}
    def __topology_owner__?, do: true
    def owner, do: raise(ArgumentError, "configuration failed")
  end

  test "a custom topology config provider can be included or used as a child without a director" do
    for collection <- [:includes, :children] do
      assert {:ok, definition} =
               Topology.new(%{
                 collection => [%{key: :child, topology: ConfigOnly}],
                 name: "parent"
               })

      assert [entry] = Map.fetch!(definition, collection)
      assert entry.topology.name == "config_only"
      if collection == :children, do: assert(entry.director == nil)
    end
  end

  test "provider exceptions, throws, and exits return structured errors with their causes" do
    for collection <- [:includes, :children],
        {provider, kind, reason} <- [
          {RaisedConfig, :error, %ArgumentError{message: "configuration failed"}},
          {ThrownConfig, :throw, :configuration_failed},
          {ExitedConfig, :exit, :configuration_failed}
        ] do
      attrs = %{collection => [%{key: :child, topology: provider}], name: "parent"}
      assert {:error, error} = Topology.new(attrs)
      assert error.message == "Topology module configuration failed"

      assert error.details == %{
               module: provider,
               kind: kind,
               reason: reason,
               source_path: [collection, 0, :topology]
             }

      assert_raise Jido.Error.ValidationError, error.message, fn -> Topology.new!(attrs) end
    end
  end

  test "child fallback and owner callback failures use the same error boundary" do
    for provider <- [RaisedTopology, RaisedOwnerFlag, RaisedOwner] do
      assert {:error, error} =
               Topology.new(name: "parent", children: [%{key: :child, topology: provider}])

      assert error.message == "Topology module configuration failed"
      assert error.details.module == provider
      assert error.details.kind == :error
      assert error.details.reason == %ArgumentError{message: "configuration failed"}
      assert error.details.source_path == [:children, 0, :topology]
    end
  end

  test "invalid returned configuration keeps its validation error" do
    assert {:error, expected} = Topology.new(nil)

    for collection <- [:includes, :children] do
      assert {:error, error} =
               Topology.new(%{
                 collection => [%{key: :child, topology: InvalidConfig}],
                 name: "parent"
               })

      assert error.message == expected.message
      refute Map.has_key?(error.details, :reason)
    end
  end

  test "child authoring rejects invalid commands, event destinations, limits, and runtime values" do
    child = %{
      key: :child,
      topology: %{name: "child", agents: [%{key: :counter, module: CounterAgent}]}
    }

    command = %{type: "counter.add", member: :counter}

    for update <- [
          %{unexpected: true},
          %{activation: :invalid},
          %{max_restarts: -1},
          %{max_seconds: 0},
          %{topology: String},
          %{topology: :unavailable_child_module},
          %{topology: 12},
          %{director: Agent.instantiate!(CounterAgent, id: "instance")},
          %{input: %{pid: self()}},
          %{gate: %{events: ["public.**"]}},
          %{gate: %{commands: [%{command | type: "counter.*"}]}},
          %{gate: %{commands: [command, command]}},
          %{gate: %{commands: [%{command | type: nil}]}},
          %{gate: %{commands: [%{command | type: "bad..path"}]}},
          %{gate: %{commands: [%{command | member: :absent}]}},
          %{gate: %{commands: [%{command | member: {:child, :absent}}]}}
        ] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Topology.new(name: "parent", children: [Map.merge(child, update)])
    end
  end

  test "child input, group command targets, directors, and parent event targets are validated during planning" do
    leaf = %{
      name: "child",
      schema: Zoi.object(%{count: Zoi.integer()}),
      groups: [%{key: :workers, module: CounterAgent, count: Topology.Reference.input(:count)}]
    }

    child = %{
      key: :team,
      topology: leaf,
      input: %{count: Topology.Reference.input(:count)},
      gate: %{commands: [%{type: "counter.add", member: {:group, :workers, "2"}}]}
    }

    definition = Topology.new!(name: "parent", schema: leaf.schema, children: [child])
    assert {:error, _} = Topology.instantiate(definition, id: "small", input: %{count: 1})
    assert {:ok, _} = Topology.instantiate(definition, id: "two", input: %{count: 2})
    bad_bus = put_in(child.gate, %{events: ["public.**"], to: :missing})

    assert {:error, _} =
             Topology.instantiate(Topology.new!(name: "parent", children: [bad_bus]), id: "bad")

    required = %{CounterAgent.definition() | schema: Zoi.object(%{required: Zoi.string()})}
    bad_director = Map.put(child, :director, required)

    assert {:error, _} =
             Topology.instantiate(
               Topology.new!(name: "parent", schema: leaf.schema, children: [bad_director]),
               id: "bad",
               input: %{count: 2}
             )
  end

  test "static include rejects runtime children instead of discarding them" do
    child = Topology.new!(name: "child", children: [%{key: :leaf, topology: %{name: "leaf"}}])

    assert {:error, error} =
             Topology.new(name: "parent", includes: [%{key: :child, topology: child}])

    assert error.message =~ "Static include"
  end

  test "Codec version 2 stays stable and new fields require version 3" do
    legacy = Topology.new!(name: "legacy", agents: [%{key: :counter, module: CounterAgent}])
    assert {:ok, %{"version" => 2} = document, registry} = Codec.encode(legacy)
    refute Map.has_key?(document, "children")
    assert {:ok, ^legacy} = Codec.decode(document, registry)
    assert {:error, _} = Codec.decode(Map.put(document, "children", []), registry)

    data =
      Topology.new!(%{legacy | agents: [%{key: :counter, definition: CounterAgent.definition()}]})

    assert {:ok, %{"version" => 3} = document, registry} = Codec.encode(data)
    assert {:ok, ^data} = Codec.decode(document, registry)
    assert {:error, _} = Codec.decode(Map.put(document, "version", 2), registry)
    assert {:error, _} = Codec.decode(Map.put(document, "version", 999), registry)
  end
end
