defmodule Jido.Codec.RegistryTest do
  use ExUnit.Case, async: true

  alias Jido.Codec.Registry
  alias JidoTest.AgentFixtures.{Add, CounterAgent}

  test "schema and constructors validate each trusted Registry kind" do
    schema = Zoi.object(%{count: Zoi.integer()})
    uri = %URI{scheme: "https", host: "example.com"}

    entries = %{
      "agents/counter" => {:agent, CounterAgent},
      "actions/add" => {:action, Add},
      "plugins/scheduler" => {:plugin, Jido.Plugin.Scheduler},
      "schemas/counter" => {:schema, schema},
      "matches/string" => {:route_match, &String.trim/1},
      "atoms/count" => {:atom, :count},
      "values/uri" => {:value, uri},
      "aliases/add" => {:alias, "actions/add"}
    }

    assert %Zoi.Types.Struct{module: Registry} = Registry.schema()
    assert {:ok, %Registry{entries: ^entries} = registry} = Registry.new(entries)
    assert Registry.stable?(registry)
    assert Registry.new!(registry) == registry
    assert {:ok, Add} = Registry.resolve(registry, "aliases/add", :action)
    assert {:ok, "actions/add"} = Registry.identifier(registry, :action, Add)
  end

  test "derived Registries stay temporary" do
    assert {:ok, %Registry{provenance: :temporary} = registry} =
             Registry.derive([{:atom, :count}])

    refute Registry.stable?(registry)
    assert {:ok, ^registry} = Registry.new(registry)
    assert {:error, %Jido.Error.ValidationError{}} = Registry.require_stable(registry)
  end

  test "Registry structs cannot bypass provenance and size validation" do
    invalid_provenance = struct(Registry, entries: %{}, provenance: :unknown)
    invalid_entries = struct(Registry, entries: %URI{}, provenance: :stable)
    oversized_entries = Map.new(0..10_000, &{Integer.to_string(&1), {:atom, :count}})
    oversized = struct(Registry, entries: oversized_entries, provenance: :stable)

    for registry <- [invalid_provenance, invalid_entries, oversized] do
      assert {:error, %Jido.Error.ValidationError{}} = Registry.new(registry)
    end
  end

  test "resolve and identifier reject unknown values and mismatched kinds" do
    registry = Registry.new!(%{"actions/add" => {:action, Add}})

    for {id, kind} <- [{"missing", :action}, {"actions/add", :flow}] do
      assert {:error, %Jido.Error.ValidationError{}} = Registry.resolve(registry, id, kind)
    end

    assert {:error, %Jido.Error.ValidationError{}} =
             Registry.identifier(registry, :action, String)
  end

  test "identifier requires exact static value identity" do
    integer = %URI{scheme: "https", host: "example.com", port: 1}
    float = %URI{scheme: "https", host: "example.com", port: 1.0}

    registry =
      Registry.new!(%{
        "values/integer" => {:value, integer},
        "values/float" => {:value, float}
      })

    assert {:ok, "values/integer"} = Registry.identifier(registry, :value, integer)
    assert {:ok, "values/float"} = Registry.identifier(registry, :value, float)

    integer_only = Registry.new!(%{"values/integer" => {:value, integer}})

    assert {:error, %Jido.Error.ValidationError{}} =
             Registry.identifier(integer_only, :value, float)
  end

  test "constructor rejects invalid identifiers, entries, values, duplicates, and aliases" do
    invalid = [
      %{},
      %{42 => {:atom, :ok}},
      %{"" => {:atom, :ok}},
      %{String.duplicate("a", 256) => {:atom, :ok}},
      %{<<255>> => {:atom, :ok}},
      %{"bad" => {:unknown, :ok}},
      %{"agent" => {:agent, String}},
      %{"plugin" => {:plugin, String}},
      %{"schema" => {:schema, :invalid}},
      %{"value" => {:value, %URI{query: self()}}},
      %{"match" => {:route_match, fn _ -> true end}},
      %{"action" => {:action, String}},
      %{"a" => {:atom, :same}, "b" => {:atom, :same}},
      %{"alias" => {:alias, "missing"}},
      %{"alias-a" => {:alias, "alias-b"}, "alias-b" => {:alias, "alias-a"}}
    ]

    assert {:ok, %Registry{entries: %{}}} = Registry.new(hd(invalid))

    for entries <- tl(invalid) do
      assert {:error, %Jido.Error.ValidationError{}} = Registry.new(entries)
    end

    assert {:error, %Jido.Error.ValidationError{}} = apply(Registry, :new, [[]])
    assert_raise Jido.Error.ValidationError, fn -> Registry.new!(%{"bad" => :entry}) end
  end
end
