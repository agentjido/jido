defmodule Jido.Agent.Directive.ConnectionUpdate do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:path, :from, :to, :changes]
  @type t :: %__MODULE__{}
end
