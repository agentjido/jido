defmodule Jido.Examples.AgentExtension do
  @moduledoc "Defines two static Agent authoring extensions."

  defmodule Label do
    @moduledoc false
    defstruct [:key, :value, :__spark_metadata__]
  end

  defmodule Flag do
    @moduledoc false
    defstruct [:name, :__spark_metadata__]
  end

  defmodule Labels do
    @moduledoc "Lowers owned label declarations into normal Agent metadata."
    @behaviour Jido.Agent.Extension

    @label %Spark.Dsl.Entity{
      name: :label,
      target: Label,
      args: [:key, :value],
      schema: [key: [type: :atom, required: true], value: [type: :any, required: true]]
    }

    use Spark.Dsl.Extension,
      dsl_patches: [%Spark.Dsl.Patch.AddEntity{section_path: [:agent], entity: @label}]

    @impl Jido.Agent.Extension
    def lower_agent(config, entities) do
      {labels, rest} = Enum.split_with(entities, &match?(%Label{}, &1))

      metadata =
        Enum.reduce(labels, config.metadata, fn label, metadata ->
          Map.put(metadata, label.key, label.value)
        end)
        |> Map.update(:extension_order, [:labels], &(&1 ++ [:labels]))

      {:ok, %{config | metadata: metadata}, rest}
    end
  end

  defmodule Flags do
    @moduledoc "Lowers owned flag declarations after the label extension."
    @behaviour Jido.Agent.Extension

    @flag %Spark.Dsl.Entity{
      name: :flag,
      target: Flag,
      args: [:name],
      schema: [name: [type: :atom, required: true]]
    }

    use Spark.Dsl.Extension,
      dsl_patches: [%Spark.Dsl.Patch.AddEntity{section_path: [:agent], entity: @flag}]

    @impl Jido.Agent.Extension
    def lower_agent(config, entities) do
      {flags, rest} = Enum.split_with(entities, &match?(%Flag{}, &1))
      names = Enum.map(flags, & &1.name)

      metadata =
        config.metadata
        |> Map.put(:flags, names)
        |> Map.update(:extension_order, [:flags], &(&1 ++ [:flags]))

      {:ok, %{config | metadata: metadata}, rest}
    end
  end

  defmodule Agent do
    @moduledoc "An ordinary validated Agent after both extensions lower."
    use Jido.Agent,
      name: "basic_agent_extension",
      extensions: [Labels, Flags]

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
      label(:owner, "examples")
      flag(:audited)
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
