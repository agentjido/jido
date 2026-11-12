defmodule Jido.Agent.Directive.Kind do
  @moduledoc false

  alias Jido.Agent.Directive

  @core_modules [
    Directive.Emit,
    Directive.Reply
  ]

  @doc false
  def core_modules, do: @core_modules

  @doc false
  def built_in?(%{__struct__: module}), do: built_in_module?(module)
  def built_in?(_value), do: false

  @doc false
  def built_in_module?(module) when is_atom(module) do
    module in @core_modules or marked?(module)
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
