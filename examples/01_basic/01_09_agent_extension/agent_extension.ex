defmodule Jido.Examples.AgentExtension do
  @moduledoc "Defines one static Agent contribution provider."

  defmodule Labels do
    @moduledoc "Stores a validated owner label in its own Agent contribution."

    @section %Spark.Dsl.Section{
      name: :labels,
      schema: [owner: [type: :string, required: true]]
    }
    @schema Zoi.object(%{owner: Zoi.string() |> Zoi.min(1)}, unrecognized_keys: :error)

    use Jido.Agent.Extension, id: "examples.labels", vsn: 1, sections: [@section]

    @impl Jido.Agent.Extension
    def lower(dsl, config) do
      {:ok, Map.put(config, :owner, Spark.Dsl.Extension.get_opt(dsl, [:labels], :owner))}
    end

    @impl Jido.Agent.Extension
    def normalize(data), do: Zoi.parse(@schema, data)
  end

  defmodule Agent do
    @moduledoc "Keeps extension data separate from core metadata and Agent state."
    use Jido.Agent,
      name: "basic_agent_extension",
      extensions: [Labels]

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    labels do
      owner("examples")
    end

    routes do
      signal_source "/examples/basic/agent_extension"

      route "examples.basic.agent_extension.add", as: :add do
        action %{amount: amount},
          schema: Zoi.object(%{amount: Zoi.integer()}),
          context: context do
          {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
        end
      end
    end
  end
end
