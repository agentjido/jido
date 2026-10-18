defmodule Jido.Agent.Directive.RouteRemove do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:path]
  @type t :: %__MODULE__{}
end
