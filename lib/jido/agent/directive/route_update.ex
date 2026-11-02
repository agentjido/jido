defmodule Jido.Agent.Directive.RouteUpdate do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:path, :changes]
  @type t :: %__MODULE__{}
end
