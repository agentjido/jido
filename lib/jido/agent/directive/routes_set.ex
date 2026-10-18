defmodule Jido.Agent.Directive.RoutesSet do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:routes]
  @type t :: %__MODULE__{}
end
