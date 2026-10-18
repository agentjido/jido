defmodule Jido.Agent.Directive.RouteAdd do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:path, :handler, as: nil, defaults: %{}, emits: nil]
  @type t :: %__MODULE__{}
end
