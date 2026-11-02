defmodule Jido.Agent.Directive.AgentUpdate do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:name, :changes]
  @type t :: %__MODULE__{}
end
