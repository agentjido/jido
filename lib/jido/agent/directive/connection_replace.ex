defmodule Jido.Agent.Directive.ConnectionReplace do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:path, :from, :to, delivery: :single]
  @type t :: %__MODULE__{}
end
