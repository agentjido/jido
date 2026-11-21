defmodule Jido.Agent.DSL.Entry do
  @moduledoc false

  defstruct [
    :path,
    :handler,
    :state,
    :reply,
    :as,
    :name,
    :provider,
    :config,
    :definition,
    :from,
    :to,
    :__spark_metadata__,
    defaults: %{},
    count: 1,
    initial_state: %{},
    delivery: :single
  ]
end
