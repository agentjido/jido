defmodule JidoTest.Agent.AuthoringExtensionTest do
  use ExUnit.Case, async: true
  alias Jido.Agent
  alias Jido.Agent.Extension

  defmodule Labels do
    @section %Spark.Dsl.Section{
      name: :labels,
      schema: [value: [type: :string, required: true]]
    }
    use Jido.Agent.Extension, id: "test.labels", sections: [@section]

    def lower(dsl, config) do
      {:ok, Map.put(config, :label, Spark.Dsl.Extension.get_opt(dsl, [:labels], :value))}
    end

    def normalize(data), do: Jido.Agent.Data.fields(data, [:label])
    def verify(%{label: "blocked"}, _), do: {:error, :blocked_label}
    def verify(_, _), do: :ok
  end

  defmodule Host do
    use Jido.Agent, name: "labels", extensions: [Labels]

    labels do
      value("accepted")
    end
  end

  defmodule DuplicateID do
    use Jido.Agent.Extension, id: "test.labels"
  end

  defmodule CoreSection do
    @section %Spark.Dsl.Section{name: :routes}
    use Jido.Agent.Extension, id: "test.core_section", sections: [@section]
  end

  defmodule CoreEndpoint do
    use Jido.Agent.Extension, id: "test.core_endpoint"
    def endpoint_kinds, do: [:agent]
  end

  defp contribution(provider, data),
    do: %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}

  test "DSL lowering and Map data produce the same contribution once" do
    entry = contribution(Labels, %{label: "accepted"})
    assert Host.definition().extensions === [entry]

    assert {:ok, definition} =
             Agent.define(%{name: "labels", module: Host, extensions: [entry]})

    assert definition === Host.definition()
    assert Agent.runtime_plugins(definition) == []
    assert Labels.runtime_support() == :none
  end

  test "provider identity and core namespaces are unique" do
    for providers <- [[Labels, Labels], [Labels, DuplicateID], [CoreSection], [CoreEndpoint]] do
      assert {:error, %Agent.Error{}} = Extension.providers(providers)
    end
  end

  test "normalization and verification reject invalid provider data" do
    for entry <- [
          contribution(Labels, %{unknown: true}),
          contribution(Labels, %{label: "blocked"}),
          contribution(Labels, %{label: self()}),
          %{contribution(Labels, %{label: "valid"}) | vsn: 99}
        ] do
      assert {:error, %Agent.Error{path: [:extensions | _]}} =
               Agent.define(%{name: "labels", extensions: [entry]})
    end
  end

  test "a provider must implement the current contribution contract" do
    assert {:error, %Agent.Error{code: :invalid_provider}} = Extension.provider(String)
    assert {:error, %Agent.Error{code: :invalid_provider}} = Extension.provider(nil)
    refute Code.ensure_loaded?(Module.concat(Extension, "RouteTarget"))
  end
end
