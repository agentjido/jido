defmodule Jido.Agent.DSL.ExtensionTest.SecondRegistryExtension do
  @moduledoc false

  @behaviour Jido.Agent.Extension

  @impl true
  def registry_values(%{binding: binding}), do: [{:binding, binding}]
end

defmodule Jido.Agent.DSL.ExtensionTest.InvalidValidationExtension do
  @moduledoc false

  @behaviour Jido.Agent.Extension

  @impl true
  def validate(_data), do: {:ok, %{agent: %{name: "mutated"}}}
end

defmodule Jido.Agent.DSL.ExtensionTest.RootMutatingCompileExtension do
  @moduledoc false

  @behaviour Jido.Agent.Extension

  @impl true
  def compile(_data, _metadata), do: {:ok, Jido.Agent.new!(name: "mutated_agent")}
end

defmodule Jido.Agent.DSL.ExtensionTest.SparkAgent do
  @moduledoc false

  use Jido.Agent,
    name: "typed_extension_agent",
    extensions: [Jido.Agent.DSL.ExtensionTest.FakeExtension.DSL]

  typed_extension do
    binding_module(Jido.Agent.DSL.ExtensionTest.FakeBinding)
    mode(:enforce)
    limit(3)
  end
end

defmodule Jido.Agent.DSL.ExtensionTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Builder
  alias Jido.Agent.Codec
  alias Jido.Agent.DSL.ExtensionTest.FakeBinding
  alias Jido.Agent.DSL.ExtensionTest.FakeExtension
  alias Jido.Agent.DSL.ExtensionTest.FakeExtension.Data
  alias Jido.Agent.DSL.ExtensionTest.InvalidValidationExtension
  alias Jido.Agent.DSL.ExtensionTest.RootMutatingCompileExtension
  alias Jido.Agent.DSL.ExtensionTest.SecondRegistryExtension
  alias Jido.Agent.DSL.ExtensionTest.SparkAgent
  alias Jido.Agent.Registry

  setup do
    Process.delete(:fake_extension_decode_called)
    :ok
  end

  defp attrs do
    %{
      name: "typed_extension_agent",
      extensions: [
        %{
          module: FakeExtension,
          data: %{binding: FakeBinding, mode: :enforce, limit: 3},
          metadata: %{owner: "typed-extension"}
        }
      ]
    }
  end

  test "one typed extension participates in every authoring boundary" do
    direct = Agent.new!(attrs())

    built =
      Builder.new("typed_extension_agent")
      |> Builder.extension(FakeExtension,
        data: %{binding: FakeBinding, mode: :enforce, limit: 3},
        metadata: %{owner: "typed-extension"}
      )
      |> Builder.build!()

    assert [%{data: %Data{binding: FakeBinding, mode: :enforce, limit: 3}}] =
             direct.extensions

    assert built == direct
    assert SparkAgent.agent() == direct

    assert {:ok, document, registry} = Codec.encode(direct)

    assert {:ok, _id} =
             Registry.identifier(
               registry,
               {:extension, FakeExtension, :binding},
               FakeBinding
             )

    json_document = document |> Jason.encode!() |> Jason.decode!()
    assert {:ok, decoded} = Codec.decode(json_document, registry)
    assert decoded == direct
    assert {:ok, ^document} = Codec.encode(decoded, registry)

    assert {:ok, compiled} = Agent.compile(decoded)

    assert compiled.extension_plans == %{
             FakeExtension => %{
               data: %Data{binding: FakeBinding, mode: :enforce, limit: 3},
               metadata: %{owner: "typed-extension"}
             }
           }
  end

  test "extension data is closed and typed" do
    assert {:error, error} =
             Agent.new(%{
               name: "closed_extension_agent",
               extensions: [
                 %{
                   module: FakeExtension,
                   data: %{binding: FakeBinding, unknown: true}
                 }
               ]
             })

    assert Exception.message(error) == "unknown fake extension field"

    direct = Agent.new!(attrs())
    assert {:ok, document, registry} = Codec.encode(direct)

    invalid =
      update_in(document, ["extensions", Access.at(0), "data"], fn data ->
        Map.put(data, "unknown", true)
      end)

    assert {:error, error} = Codec.decode(invalid, registry)
    assert Exception.message(error) == "invalid fake extension document"
    assert error.details.path == ["extensions", 0, "data"]
  end

  test "namespaced extension Registry kinds cannot collide" do
    agent =
      Agent.new!(
        name: "extension_registry_agent",
        plugin_defaults: :none,
        extensions: [
          %{module: FakeExtension, data: %{binding: FakeBinding}},
          %{module: SecondRegistryExtension, data: %{binding: FakeBinding}}
        ]
      )

    assert {:ok, registry} = Registry.from_agent(agent)
    first_kind = {:extension, FakeExtension, :binding}
    second_kind = {:extension, SecondRegistryExtension, :binding}

    assert {:ok, first_id} = Registry.identifier(registry, first_kind, FakeBinding)
    assert {:ok, second_id} = Registry.identifier(registry, second_kind, FakeBinding)
    refute first_id == second_id
    assert {:ok, FakeBinding} = Registry.resolve(registry, first_id, first_kind)
    assert {:ok, FakeBinding} = Registry.resolve(registry, second_id, second_kind)
    assert {:error, _error} = Registry.resolve(registry, first_id, second_kind)
  end

  test "Codec limits fail before an extension decode callback" do
    direct = Agent.new!(attrs())
    assert {:ok, document, registry} = Codec.encode(direct)
    Process.delete(:fake_extension_decode_called)
    deep = Enum.reduce(1..101, 0, fn _index, value -> [value] end)

    invalid =
      update_in(document, ["extensions", Access.at(0), "data"], fn _data -> deep end)

    assert {:error, error} = Codec.decode(invalid, registry)
    assert Exception.message(error) == "stored Agent exceeds its nesting limit"
    refute Process.get(:fake_extension_decode_called)
  end

  test "validation cannot return normalized or root mutation data" do
    assert {:error, error} =
             Agent.new(
               name: "invalid_extension_validation",
               extensions: [%{module: InvalidValidationExtension, data: %{}}]
             )

    assert Exception.message(error) ==
             "Agent extension structural validation returned an invalid value"
  end

  test "compile contribution cannot return a root mutation" do
    agent =
      Agent.new!(
        name: "invalid_extension_compile",
        plugin_defaults: :none,
        extensions: [%{module: RootMutatingCompileExtension, data: %{}}]
      )

    assert {:error, error} = Agent.compile(agent)
    assert Exception.message(error) == "Agent extension compilation cannot return a root Agent"
  end

  test "version 1 has no extension dependency callback" do
    callbacks = Jido.Agent.Extension.behaviour_info(:callbacks)

    refute {:dependencies, 0} in callbacks
    refute {:extension_dependencies, 1} in callbacks
  end
end
