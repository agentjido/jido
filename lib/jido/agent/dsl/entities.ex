defmodule Jido.Agent.DSL.Plugin do
  @moduledoc false

  defstruct [
    :module,
    :__identifier__,
    __source__: %{},
    __spark_metadata__: nil,
    as: nil,
    config: %{},
    metadata: %{}
  ]
end

defmodule Jido.Agent.DSL.Route do
  @moduledoc false

  defstruct [
    :path,
    :target,
    :__identifier__,
    __source__: %{},
    __spark_metadata__: nil,
    match: nil,
    priority: 0,
    params: %{}
  ]
end

defmodule Jido.Agent.DSL.Schedule do
  @moduledoc false

  defstruct [
    :name,
    :cron_expression,
    :signal_type,
    :__identifier__,
    __source__: %{},
    __spark_metadata__: nil,
    timezone: "Etc/UTC",
    data: %{},
    metadata: %{}
  ]
end
