defmodule Jido.Agent.Directive.PluginRemove do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:module, :state]
  @type t :: %__MODULE__{}
end
