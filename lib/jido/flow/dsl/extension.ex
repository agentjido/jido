defmodule Jido.Flow.DSL.Extension do
  @moduledoc false

  [flow] = Jido.Flow.DSL.Schema.sections()

  use Spark.Dsl.Extension,
    sections: [%{flow | imports: [Jido.Flow.DSL.Macros]}]
end

defmodule Jido.Flow.DSL do
  @moduledoc false

  use Spark.Dsl,
    default_extensions: [
      extensions: [Jido.Flow.DSL.Extension]
    ]
end
