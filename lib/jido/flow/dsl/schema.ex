defmodule Jido.Flow.DSL.Schema do
  @moduledoc false

  alias Jido.Flow.DSL.{
    Choice,
    Handoff,
    Invoke,
    Iterate,
    MapNode,
    Output,
    Parallel,
    Reduce,
    Step
  }

  @flow %Spark.Dsl.Section{
    name: :flow,
    describe: "Declares a Jido Flow graph.",
    entities: [
      Step.entity(),
      Jido.Flow.DSL.Timer.entity(),
      Jido.Flow.DSL.Await.entity(),
      Jido.Flow.DSL.Selection.entity(),
      Choice.entity(),
      MapNode.entity(),
      Parallel.entity(),
      Reduce.entity(),
      Iterate.entity(),
      Invoke.entity(),
      Handoff.entity(),
      Output.entity()
    ],
    singleton_entity_keys: [:output]
  }

  @doc false
  @spec sections() :: [Spark.Dsl.Section.t()]
  def sections, do: [@flow]
end
