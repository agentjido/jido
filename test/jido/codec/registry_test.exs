defmodule Jido.Codec.RegistryTest do
  use Covenant.Case, component: "jido_action.authoring", async: true
  @moduletag obligation: "jido_action.authoring.I1"

  alias Jido.Codec.Registry
  alias Jido.Codec.Registry.Error

  test "stores typed entries and resolves exact versioned references" do
    registry =
      Registry.new!(%{
        {"actions/add", 1} => {:action, __MODULE__},
        {"atoms/count", 1} => {:atom, :count}
      })

    assert {:ok, {"actions/add", 1}} =
             Registry.reference(registry, :action, __MODULE__)

    assert {:error, %Error{} = error} =
             Registry.resolve(registry, {"actions/add", 1}, :flow)

    assert Jido.Codec.Error.splode_error?(error)
  end

  test "accepting an existing Registry preserves its discovered metadata" do
    assert {:ok, discovered} =
             Registry.new_discovered([], [
               %{type: "tests.codec", vsn: 1, target: nil, module: __MODULE__}
             ])

    assert {:ok, ^discovered} = Registry.new(discovered)
    assert Registry.codec(discovered, "tests.codec", 1) == {:ok, __MODULE__}
  end

  test "keeps historical readers and selects one current writer" do
    old_one = %{type: "tests.versioned", vsn: 1, target: nil, module: String}
    old_two = %{type: "tests.versioned", vsn: 2, target: nil, module: List}
    current = %{type: "tests.versioned", vsn: 3, target: URI, module: URI}

    assert {:ok, registry} = Registry.new_discovered([], [current, old_two, old_one])
    assert Registry.codec_vsns(registry, "tests.versioned") == [1, 2, 3]
    assert Registry.codec(registry, "tests.versioned", 1) == {:ok, String}
    assert Registry.codec(registry, "tests.versioned", 2) == {:ok, List}
    assert Registry.codec(registry, "tests.versioned", 3) == {:ok, URI}
    assert Registry.encoder(registry, %URI{}) == {:ok, URI}
  end

  test "rejects duplicate document routes and duplicate current writers" do
    assert {:error, {:duplicate_codec_codec, {"tests.duplicate", 1}}} =
             Registry.new_discovered([], [
               %{type: "tests.duplicate", vsn: 1, target: nil, module: String},
               %{type: "tests.duplicate", vsn: 1, target: nil, module: List}
             ])

    assert {:error, {:duplicate_codec_target, URI}} =
             Registry.new_discovered([], [
               %{type: "tests.one", vsn: 1, target: URI, module: String},
               %{type: "tests.two", vsn: 1, target: URI, module: List}
             ])
  end

  test "uses vsn as part of every portable reference" do
    registry =
      Registry.new!(%{
        {"actions/add", 1} => {:action, :old},
        {"actions/add", 2} => {:action, __MODULE__}
      })

    assert {:ok, {"actions/add", 2}} =
             Registry.reference(registry, :action, __MODULE__)

    assert {:ok, __MODULE__} =
             Registry.resolve(registry, {"actions/add", 2}, :action)

    assert {:ok, :old} =
             Registry.resolve(registry, {"actions/add", 1}, :action)

    assert {:error, %Error{details: %{identifier: "actions/add", vsn: 3}}} =
             Registry.resolve(registry, {"actions/add", 3}, :action)
  end

  test "owns the common reference document format" do
    registry =
      Registry.new!(%{
        {"extensions/sample", 1} => {:extension, __MODULE__},
        {"plugins/sample", 1} => {:plugin, :sample}
      })

    assert {:ok, %{"id" => "extensions/sample", "vsn" => 1} = document} =
             Registry.encode_reference(registry, [:extension, :plugin], __MODULE__)

    assert {:ok, __MODULE__} =
             Registry.decode_reference(registry, document, [:extension, :plugin])

    assert {:error, %Error{details: %{field: "extra"}}} =
             Registry.decode_reference(
               registry,
               Map.put(document, "extra", true),
               :extension
             )

    assert {:error, %Error{details: %{actual: :extension}}} =
             Registry.decode_reference(registry, document, :plugin)
  end

  test "rejects versionless keys references and entries" do
    assert {:error, %Error{}} = Registry.new(%{"atoms/value" => {:atom, :value}})
    assert {:error, %Error{}} = Registry.new(%{{"atoms/value", 1} => {:atom, 1, :value}})
    assert {:error, %Error{}} = Registry.new(%{{"atoms/old", 1} => {:alias, {"atoms/value", 1}}})

    registry = Registry.new!(%{{"atoms/value", 1} => {:atom, :value}})
    assert {:error, %Error{}} = Registry.resolve(registry, "atoms/value", :atom)
    assert {:error, %Error{}} = Registry.resolve(registry, %{"id" => "atoms/value"}, :atom)
  end

  test "unknown identifiers do not create atoms" do
    registry = Registry.new!(%{})
    identifier = "missing/#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, fn -> String.to_existing_atom(identifier) end

    assert {:error, %Error{}} =
             Registry.resolve(registry, {identifier, 1}, :action)

    assert_raise ArgumentError, fn -> String.to_existing_atom(identifier) end
  end

  test "rejects invalid identifiers duplicate writes and oversized maps" do
    for entries <- [
          %{nil => {:atom, :ok}},
          %{{"bad space", 1} => {:atom, :ok}},
          %{{String.duplicate("a", 256), 1} => {:atom, :ok}},
          %{{"bad", 1} => :entry},
          %{{"alias", 1} => {:alias, :value}},
          %{{"one", 1} => {:atom, :same}, {"two", 1} => {:atom, :same}}
        ] do
      assert {:error, %Error{}} = Registry.new(entries)
    end

    oversized = Map.new(0..10_000, &{{Integer.to_string(&1), 1}, {:atom, &1}})
    assert {:error, %Error{}} = Registry.new(oversized)
  end
end
