defmodule Jido.Agent.DSL do
  @moduledoc false

  use Spark.Dsl,
    default_extensions: [extensions: [Jido.Agent.DSL.Extension]]
end
