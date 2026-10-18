# Authoring Extensions

An extension adds static Agent declarations. Use `Jido.Agent.Extension` for
both DSL and map contributions. It does not start runtime work.

## Define A Provider

```elixir
defmodule MyApp.Labels do
  @section %Spark.Dsl.Section{
    name: :labels,
    schema: [owner: [type: :string, required: true]]
  }
  @schema Zoi.object(%{owner: Zoi.string() |> Zoi.min(1)}, unrecognized_keys: :error)

  use Jido.Agent.Extension, id: "app.labels", vsn: 1, sections: [@section]

  @impl Jido.Agent.Extension
  def lower(dsl, config) do
    {:ok, Map.put(config, :owner, Spark.Dsl.Extension.get_opt(dsl, [:labels], :owner))}
  end

  @impl Jido.Agent.Extension
  def normalize(data), do: Zoi.parse(@schema, data)
end

defmodule MyApp.LabelledAgent do
  use Jido.Agent, name: "labelled_agent", extensions: [MyApp.Labels]

  agent do
    schema Zoi.object(%{})
  end

  labels do
    owner "app"
  end
end

{:ok, definition} = MyApp.LabelledAgent.definition()
[%{provider: MyApp.Labels, data: %{owner: "app"}}] = definition.extensions
```

`c:Jido.Agent.Extension.lower/2` reads Spark declarations and explicit config.
`c:Jido.Agent.Extension.normalize/1` validates contribution data from both the
DSL and maps. `c:Jido.Agent.Extension.verify/2` checks references after core
normalization. The provider ID and version identify the stored contribution.

## Keep Contributions Static

Jido stores contributions in `agent.extensions`, separate from core metadata
and Agent state. Declare core topology Agents and connections on the Agent.
Use `Jido.Agent.define/1` for direct definitions. The Codec uses the same
contribution validation.

Callbacks must give deterministic results. They must not start processes, run
Actions or Flows, or contact services. `runtime_support/0` describes optional
runtime support; Agent definition code does not activate it.

See [the extension example](../examples/01_basic/01_09_agent_extension/README.md),
[Data Definitions and Codecs](data-definitions-and-codecs.md), and
[Extension Boundaries](extension-boundaries.md).
