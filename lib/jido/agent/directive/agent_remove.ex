defmodule Jido.Agent.Directive.AgentRemove do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:name]
  @type t :: %__MODULE__{}
end
