defmodule Jido.Agent.Directive.Kind do
  @moduledoc false

  alias Jido.Agent.Directive

  @core_modules [
    Directive.Emit,
    Directive.Reply,
    Directive.AgentSend,
    Directive.ParentSend,
    Directive.ServerStop
  ]

  @mutation_modules [
    Directive.AgentAdd,
    Directive.AgentUpdate,
    Directive.AgentReplace,
    Directive.AgentRemove,
    Directive.RouteAdd,
    Directive.RouteUpdate,
    Directive.RouteReplace,
    Directive.RouteRemove,
    Directive.RoutesSet,
    Directive.RoutesReorder,
    Directive.ConnectionAdd,
    Directive.ConnectionUpdate,
    Directive.ConnectionReplace,
    Directive.ConnectionRemove,
    Directive.TopologySet,
    Directive.PluginAdd,
    Directive.PluginConfigure,
    Directive.PluginRemove
  ]

  @doc false
  def core_modules, do: @core_modules

  @doc false
  def mutation_modules, do: @mutation_modules

  @doc false
  def mutation_module?(module) when is_atom(module), do: module in @mutation_modules
  def mutation_module?(_module), do: false

  @doc false
  def built_in?(%{__struct__: module}), do: built_in_module?(module)
  def built_in?(_value), do: false

  @doc false
  def built_in_module?(module) when is_atom(module) do
    module in @core_modules or module in @mutation_modules or marked?(module)
  end

  def built_in_module?(_module), do: false

  @doc false
  def validator?(module) when is_atom(module),
    do: built_in_module?(module) or function_exported?(module, :validate, 1)

  def validator?(_module), do: false

  defp marked?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__jido_builtin_directive__, 0) and
      module.__jido_builtin_directive__() == true
  end
end
