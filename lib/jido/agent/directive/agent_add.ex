defmodule Jido.Agent.Directive.AgentAdd do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:name, :definition, count: 1, initial_state: %{}]
  @type t :: %__MODULE__{}
end
