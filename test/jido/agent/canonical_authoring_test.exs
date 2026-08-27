defmodule Jido.Agent.CanonicalAuthoringTest.Parity do
  @moduledoc false

  def schema do
    Zoi.object(%{
      count:
        Zoi.integer()
        |> Zoi.refine({__MODULE__, :nonnegative, []})
        |> Zoi.default(0)
    })
  end

  def nonnegative(value), do: if(value < 0, do: {:error, "must be nonnegative"}, else: :ok)
  def selected?(_signal), do: true
end

defmodule Jido.Agent.CanonicalAuthoringTest.SparkAgent do
  @moduledoc false

  use Jido.Agent,
    name: "canonical_spark_agent",
    description: "Canonical Agent parity",
    extensions: [Jido.Agent.DSL.ExtensionTest.FakeExtension.DSL],
    metadata: %{
      "string-key" => "value",
      7 => %{integer_key: true},
      owner: :core
    }

  agent do
    state_schema(Jido.Agent.CanonicalAuthoringTest.Parity.schema())
    plugin_defaults(:none)

    plugin(JidoTest.TestAgents.TestPluginWithRoutes,
      as: :support,
      config: %{token: "primary"},
      metadata: %{owner: "spark"}
    )

    plugin(JidoTest.TestAgents.TestPluginWithRoutes,
      as: :backup,
      config: %{token: "secondary"}
    )

    route("agent.tick", JidoTest.TestActions.NoSchema,
      match: &Jido.Agent.CanonicalAuthoringTest.Parity.selected?/1,
      params: %{amount: 1, source: :spark},
      priority: 3
    )

    schedule("tick", "*/5 * * * *", "agent.tick",
      data: %{amount: 1, mode: :ready},
      metadata: %{owner: "spark"}
    )
  end

  typed_extension do
    binding_module(Jido.Agent.DSL.ExtensionTest.FakeBinding)
    mode(:enforce)
    limit(3)
  end
end

defmodule Jido.Agent.CanonicalAuthoringTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Builder
  alias Jido.Agent.CanonicalAuthoringTest.Parity
  alias Jido.Agent.CanonicalAuthoringTest.SparkAgent
  alias Jido.Agent.Codec
  alias Jido.Agent.DSL.ExtensionTest.FakeBinding
  alias Jido.Agent.DSL.ExtensionTest.FakeExtension
  alias Jido.Agent.Plugin
  alias Jido.Agent.Registry
  alias Jido.Agent.Schedule

  test "direct, Builder, Spark, and JSON authoring produce one full canonical Agent" do
    direct = direct_agent()

    built =
      Builder.new("canonical_spark_agent")
      |> Builder.description("Canonical Agent parity")
      |> Builder.state_schema(Parity.schema())
      |> Builder.plugin_defaults(:none)
      |> Builder.plugin(JidoTest.TestAgents.TestPluginWithRoutes,
        as: :support,
        config: %{token: "primary"},
        metadata: %{owner: "spark"}
      )
      |> Builder.plugin(JidoTest.TestAgents.TestPluginWithRoutes,
        as: :backup,
        config: %{token: "secondary"}
      )
      |> Builder.route("agent.tick", JidoTest.TestActions.NoSchema,
        match: &Parity.selected?/1,
        params: %{amount: 1, source: :spark},
        priority: 3
      )
      |> Builder.schedule("tick", "*/5 * * * *", "agent.tick",
        data: %{amount: 1, mode: :ready},
        metadata: %{owner: "spark"}
      )
      |> Builder.extension(FakeExtension,
        data: %{binding: FakeBinding, mode: :enforce, limit: 3},
        metadata: %{owner: "typed-extension"}
      )
      |> Builder.metadata(%{
        "string-key" => "value",
        7 => %{integer_key: true},
        owner: :core
      })
      |> Builder.build!()

    assert built == direct
    assert SparkAgent.agent() == direct

    assert {:ok, document, registry} = Codec.encode(direct)
    json_document = document |> Jason.encode!() |> Jason.decode!()
    assert {:ok, decoded} = Codec.decode(json_document, registry)
    assert decoded == direct
    assert {:ok, ^document} = Codec.encode(decoded, registry)

    identities =
      Enum.map([direct, built, SparkAgent.agent(), decoded], fn agent ->
        assert {:ok, identity} = Agent.semantic_identity(agent)
        identity
      end)

    assert Enum.uniq(identities) == [hd(identities)]
    assert length(direct.plugins) == 2
    assert hd(direct.plugins).as == :support
    assert direct.plugin_defaults.mode == :none
    assert direct.metadata[7] == %{integer_key: true}
  end

  test "Registry aliases, source maps, and host defaults do not alter value or identity" do
    direct = direct_agent()
    assert {:ok, identity} = Agent.semantic_identity(direct)
    assert {:ok, document, registry} = Codec.encode(direct)

    kind = {:extension, FakeExtension, :binding}
    assert {:ok, canonical_id} = Registry.identifier(registry, kind, FakeBinding)
    alias_id = "extension-values/binding-alias"
    alias_registry = Registry.new!(Map.put(registry.entries, alias_id, {:alias, canonical_id}))

    alias_document =
      put_in(document, ["extensions", Access.at(0), "data", "binding"], alias_id)

    assert {:ok, alias_decoded} = Codec.decode(alias_document, alias_registry)
    assert alias_decoded == direct
    assert {:ok, ^identity} = Agent.semantic_identity(alias_decoded)

    source_map = SparkAgent.__jido_agent_source_map__()
    assert {:ok, compiled_with_source} = Agent.compile(direct, source_map: source_map)
    assert compiled_with_source.agent == direct
    assert compiled_with_source.semantic_identity == identity
    assert compiled_with_source.source_map == source_map
    refute Map.has_key?(Map.from_struct(direct), :source_map)

    assert {:ok, compiled_with_host_defaults} =
             Agent.compile(direct, default_plugins: [Jido.Thread.Plugin])

    assert compiled_with_host_defaults.agent == direct
    assert compiled_with_host_defaults.semantic_identity == identity
    assert Agent.semantic_identity(direct) == {:ok, identity}
  end

  defp direct_agent do
    Agent.new!(
      name: "canonical_spark_agent",
      description: "Canonical Agent parity",
      state_schema: Parity.schema(),
      plugin_defaults: :none,
      plugins: [
        Plugin.new!(
          module: JidoTest.TestAgents.TestPluginWithRoutes,
          as: :support,
          config: %{token: "primary"},
          metadata: %{owner: "spark"}
        ),
        Plugin.new!(
          module: JidoTest.TestAgents.TestPluginWithRoutes,
          as: :backup,
          config: %{token: "secondary"}
        )
      ],
      routes: [
        {"agent.tick", &Parity.selected?/1, JidoTest.TestActions.NoSchema,
         %{amount: 1, source: :spark}, 3}
      ],
      schedules: [
        Schedule.new!(
          name: "tick",
          cron_expression: "*/5 * * * *",
          signal_type: "agent.tick",
          data: %{amount: 1, mode: :ready},
          metadata: %{owner: "spark"}
        )
      ],
      extensions: [
        %{
          module: FakeExtension,
          data: %{binding: FakeBinding, mode: :enforce, limit: 3},
          metadata: %{owner: "typed-extension"}
        }
      ],
      metadata: %{
        "string-key" => "value",
        7 => %{integer_key: true},
        owner: :core
      }
    )
  end
end
