defmodule Jido.Examples.AuthoringPlugin do
  @moduledoc "Defines one authoring-only Plugin."

  defmodule Labels do
    @moduledoc "Stores a validated owner label in its own Agent contribution."
    alias Spark.Dsl.Extension, as: SparkExtension

    @section %Spark.Dsl.Section{
      name: :labels,
      schema: [owner: [type: :string, required: true]]
    }
    @schema Zoi.object(%{owner: Zoi.string() |> Zoi.min(1)}, unrecognized_keys: :error)

    use Jido.Plugin, id: "examples.labels", vsn: 1, sections: [@section]

    @impl true
    def lower(dsl, config) do
      {:ok, Map.put(config, :owner, SparkExtension.get_opt(dsl, [:labels], :owner))}
    end

    @impl true
    def normalize(data), do: Zoi.parse(@schema, data)
  end

  defmodule Agent do
    @moduledoc "Keeps Plugin data separate from core metadata and Agent state."
    use Jido.Agent,
      name: "basic_authoring_plugin",
      plugins: [Labels]

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    labels do
      owner("examples")
    end

    routes do
      signal_source "/examples/basic/authoring_plugin"

      route "examples.basic.authoring_plugin.add", as: :add do
        action %{amount: amount},
          schema: Zoi.object(%{amount: Zoi.integer()}),
          context: context do
          {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
        end
      end
    end
  end
end
