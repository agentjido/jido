defmodule Jido.Agent.Directive.PluginAdd do
  @moduledoc "Agent data mutation. Validated by `Jido.Agent.mutate/2`."
  defstruct [:module, options: [], initial: :default]
  @type t :: %__MODULE__{}
end
