defmodule JidoTest.Agent.AuthoringExtensionTest do
  use Covenant.Case, component: "jido.agent", async: true
  alias Jido.Agent
  alias Jido.Agent.Extension

  defmodule Labels do
    alias Spark.Dsl.Extension, as: SparkExtension

    @section %Spark.Dsl.Section{
      name: :labels,
      schema: [value: [type: :string, required: true]]
    }
    use Jido.Plugin, id: "test.labels", sections: [@section]

    def lower(dsl, config) do
      {:ok, Map.put(config, :label, SparkExtension.get_opt(dsl, [:labels], :value))}
    end

    def normalize(data), do: Jido.Agent.Data.fields(data, [:label])
    def verify(%{label: "blocked"}, _), do: {:error, :blocked_label}
    def verify(_, _), do: :ok
  end

  defmodule Host do
    use Jido.Agent, name: "labels", plugins: [Labels]

    labels do
      value("accepted")
    end
  end

  defmodule DuplicateID do
    use Jido.Plugin, id: "test.labels"
  end

  defmodule CoreEndpoint do
    use Jido.Plugin, id: "test.core_endpoint"
    def endpoint_kinds, do: [:agent]
  end

  defmodule Boundary do
    use Jido.Plugin, id: "test.boundary", vsn: 7

    def lower(dsl, config), do: {:ok, %{dsl: dsl, config: config}}
    def normalize(%{reject: reason}), do: {:error, reason}
    def normalize(data), do: {:ok, data}
    def endpoint_kinds, do: [:boundary]
    def endpoints(data), do: [Map.fetch!(data, :endpoint)]
  end

  defmodule RouteTarget do
    use Jido.Action, name: "extension_route_target"
    def run(params, _context), do: {:ok, params}
  end

  defmodule OtherRouteTarget do
    use Jido.Action, name: "other_extension_route_target"
    def run(params, _context), do: {:ok, params}
  end

  defmodule Routed do
    use Jido.Plugin, id: "test.routed"

    @impl Jido.Agent.Extension
    def normalize(%{target: target}), do: {:ok, %{target: target}}

    @impl Jido.Agent.Extension
    def derive_routes(%{target: target}) do
      [
        %{
          path: "extension.request",
          as: :extension,
          defaults: %{},
          handler: %{kind: :action, target: target},
          state: %{source: :output, path: []},
          reply: nil
        }
      ]
    end
  end

  defmodule NoSections do
    @behaviour Jido.Agent.Extension

    def id, do: "test.no_sections"
    def vsn, do: 1
    def lower(_dsl, config), do: {:ok, config}
    def normalize(data), do: {:ok, data}
    def verify(_data, _definition), do: :ok
    def endpoint_kinds, do: []
    def endpoints(_data), do: []
    def verify_connection(_data, _connection), do: :ok
  end

  for {section, suffix} <- [
        agent: "CoreAgent",
        state: "CoreState",
        routes: "CoreRoutes",
        topology: "CoreTopology",
        __state__: "CorePrivateState",
        __routes__: "CorePrivateRoutes",
        __topology__: "CorePrivateTopology"
      ] do
    module = Module.concat(__MODULE__, suffix)
    id = "test.core.#{section}"

    Module.create(
      module,
      quote do
        @section %Spark.Dsl.Section{name: unquote(section)}
        use Jido.Plugin, id: unquote(id), sections: [@section]
      end,
      Macro.Env.location(__ENV__)
    )
  end

  defp contribution(provider, data),
    do: %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}

  @tag obligation: ["jido.agent.I1", "jido.agent.I10"]
  test "DSL lowering and Map data produce the same contribution once" do
    entry = contribution(Labels, %{label: "accepted"})
    assert Host.definition().plugins === [entry]

    assert {:ok, definition} =
             Agent.define(%{name: "labels", module: Host, plugins: [entry]})

    assert definition === Host.definition()
    assert Agent.runtime_plugins(definition) == []
    refute function_exported?(Labels, :__jido_plugin__, 0)
  end

  @tag obligation: "jido.agent.I10"
  test "provider identity and core namespaces are unique" do
    for providers <- [[Labels, Labels], [Labels, DuplicateID], [CoreEndpoint]] do
      assert {:error, %Agent.Error{}} = Extension.providers(providers)
    end
  end

  for {section, suffix} <- [
        agent: "CoreAgent",
        state: "CoreState",
        routes: "CoreRoutes",
        topology: "CoreTopology",
        __state__: "CorePrivateState",
        __routes__: "CorePrivateRoutes",
        __topology__: "CorePrivateTopology"
      ] do
    provider = Module.concat(__MODULE__, suffix)

    @tag obligation: "jido.agent.I10"
    test "#{section} is a reserved provider section" do
      assert {:error,
              %Agent.Error{
                code: :namespace_conflict,
                message: message
              }} = Extension.providers([unquote(provider)])

      assert message != ""
    end
  end

  @tag obligation: ["jido.agent.I10", "jido.agent.I22"]
  test "provider validation uses the complete contribution behavior" do
    assert Enum.sort(Extension.behaviour_info(:callbacks)) ===
             Enum.sort(
               id: 0,
               vsn: 0,
               lower: 2,
               normalize: 1,
               verify: 2,
               encode_authoring_data: 2,
               decode_authoring_data: 2,
               derive_routes: 1,
               endpoint_kinds: 0,
               endpoints: 1,
               verify_connection: 2
             )

    assert Enum.sort(Extension.behaviour_info(:optional_callbacks)) ==
             Enum.sort(
               encode_authoring_data: 2,
               decode_authoring_data: 2,
               derive_routes: 1
             )

    for value <- [NoSections, String, nil, true, false, 1, "module", %{}] do
      assert {:error,
              %Agent.Error{
                code: :invalid_provider,
                message: message,
                details: %{provider: ^value}
              }} = Extension.provider(value)

      assert message != ""
    end
  end

  @tag obligation: "jido.agent.I10"
  test "lowering and endpoint projection return the complete contribution" do
    dsl = %{source: "dsl"}
    config = %{option: 1}
    data = %{dsl: dsl, config: config}
    entry = contribution(Boundary, data)

    assert {:ok, [^entry]} =
             Extension.lower([%{provider: Boundary, config: config}], dsl)

    endpoint = %{kind: :boundary, name: :output}
    assert Extension.endpoints([contribution(Boundary, %{endpoint: endpoint})]) === [endpoint]
  end

  @tag obligation: ["jido.agent.I10", "jido.agent.I22"]
  test "a Plugin contributes one exact route through Map authoring" do
    entry = contribution(Routed, %{target: RouteTarget})

    assert {:ok, definition} =
             Agent.define(%{name: "routed", signal_source: "/routed", plugins: [entry]})

    assert [route] = definition.routes
    assert route.path == "extension.request"
    assert route.handler == %{kind: :action, target: RouteTarget}

    assert {:ok, same} =
             definition
             |> Map.from_struct()
             |> Agent.define()

    assert same == definition
  end

  @tag obligation: ["jido.agent.I10", "jido.agent.I22"]
  test "stored route projection requires every derived route" do
    entry = contribution(Routed, %{target: RouteTarget})

    assert {:error,
            %Agent.Error{
              code: :missing_derived_route,
              path: [:plugins, 0, :routes, 0],
              details: %{path: "extension.request", provider: Routed}
            }} = Extension.stored_routes([entry], [])
  end

  @tag obligation: ["jido.agent.I10", "jido.agent.I22"]
  test "a Plugin route cannot conflict with a stored route" do
    entry = contribution(Routed, %{target: RouteTarget})

    conflicting = %{
      path: "extension.request",
      handler: %{kind: :action, target: OtherRouteTarget},
      state: %{source: :output, path: []}
    }

    assert {:error,
            %Agent.Error{
              code: :plugin_route_conflict,
              path: [:routes, 0],
              details: %{path: "extension.request", provider: Routed}
            }} =
             Agent.define(%{
               name: "routed",
               signal_source: "/routed",
               routes: [conflicting],
               plugins: [entry]
             })
  end

  @tag obligation: ["jido.agent.I10", "jido.agent.I22"]
  test "a Plugin can contribute only exact routes" do
    wildcard = Module.concat(__MODULE__, "Wildcard#{System.unique_integer([:positive])}")
    id = "test.wildcard.#{System.unique_integer([:positive])}"

    Module.create(
      wildcard,
      quote do
        use Jido.Plugin, id: unquote(id)
        @impl Jido.Agent.Extension
        def derive_routes(_data), do: [%{path: "extension.*"}]
      end,
      Macro.Env.location(__ENV__)
    )

    entry = contribution(wildcard, %{})

    assert {:error,
            %Agent.Error{
              code: :wildcard_type,
              path: [:plugins, 0, :routes, 0, :path]
            }} = Agent.define(%{name: "wildcard", plugins: [entry]})
  end

  @tag obligation: ["jido.agent.I10", "jido.agent.I22"]
  test "normalization and verification reject invalid provider data" do
    for entry <- [
          contribution(Labels, %{unknown: true}),
          contribution(Labels, %{label: "blocked"}),
          contribution(Labels, %{label: self()}),
          %{contribution(Labels, %{label: "valid"}) | vsn: 99}
        ] do
      assert {:error, %Agent.Error{path: [:plugins | _]}} =
               Agent.define(%{name: "labels", plugins: [entry]})
    end

    rejected = contribution(Boundary, %{reject: :bad_data})

    assert {:error,
            %Agent.Error{
              code: :provider_error,
              message: message,
              details: %{reason: :bad_data}
            }} = Extension.normalize([rejected])

    assert message != ""
  end

  @tag obligation: "jido.agent.I22"
  test "a provider must implement the current contribution contract" do
    assert {:error,
            %Agent.Error{
              code: :invalid_provider,
              message: message,
              details: %{provider: String}
            }} = Extension.provider(String)

    assert message != ""
    refute Code.ensure_loaded?(Module.concat(Extension, "RouteTarget"))
  end
end
