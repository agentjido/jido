defmodule Jido.Agent.DSL.Schedule do
  @moduledoc false
  alias Jido.Agent.Schedules
  defstruct [:__spark_metadata__ | Keyword.keys(Schedules.schema())]
end

defmodule Jido.Agent.DSL.Schedules do
  @moduledoc false
  alias Jido.Agent.{Authoring, Schedules}
  alias Spark.Dsl.Extension

  @schedule %Spark.Dsl.Entity{
    name: :schedule,
    target: Jido.Agent.DSL.Schedule,
    args: [:key],
    schema: Authoring.dsl_schema(Schedules.schema())
  }

  use Spark.Dsl.Extension,
    sections: [%Spark.Dsl.Section{name: :schedules, entities: [@schedule]}]

  def lower(dsl) do
    Enum.map(
      Extension.get_entities(dsl, [:schedules]),
      &Authoring.dsl_fields(&1, Schedules.schema())
    )
  end
end
