defmodule Jido.Agent.Directive.PluginConfigure do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:module, :migrate, options: []]
  @type t :: %__MODULE__{}
end
