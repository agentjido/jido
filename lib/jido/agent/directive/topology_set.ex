defmodule Jido.Agent.Directive.TopologySet do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:topology]
  @type t :: %__MODULE__{}
end
