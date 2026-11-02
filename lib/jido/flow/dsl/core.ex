defmodule Jido.Flow.DSL.Core do
  @moduledoc false

  alias Jido.Flow.DSL.{Output, Step}

  @flow %Spark.Dsl.Section{
    name: :flow,
    describe: "Declares a canonical Jido Flow.",
    entities: [Step.entity(), Output.entity()],
    patchable?: true,
    singleton_entity_keys: [:output],
    imports: [Jido.Flow.DSL.Macros]
  }

  use Spark.Dsl.Extension,
    sections: [@flow]
end

defmodule Jido.Flow.DSL do
  @moduledoc false

  use Spark.Dsl,
    default_extensions: [
      extensions: [Jido.Flow.DSL.Core, Jido.Flow.DSL.Forms]
    ]
end
