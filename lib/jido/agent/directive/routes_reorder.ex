defmodule Jido.Agent.Directive.RoutesReorder do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:paths]
  @type t :: %__MODULE__{}
end
