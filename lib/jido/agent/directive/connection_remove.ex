defmodule Jido.Agent.Directive.ConnectionRemove do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:path, :from, :to]
  @type t :: %__MODULE__{}
end
