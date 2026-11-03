defmodule Jido.Exec.NestedCompiler do
  @moduledoc false

  alias Jido.Instruction
  alias Runic.Workflow

  @callback compile_nested!(Instruction.t(), keyword()) :: Workflow.t() | no_return()

  @doc false
  @spec validate!(module()) :: module()
  def validate!(module) when is_atom(module) and not is_nil(module) do
    if function_exported?(module, :compile_nested!, 2) do
      module
    else
      raise ArgumentError, "nested compiler must implement compile_nested!/2"
    end
  end

  def validate!(_module), do: raise(ArgumentError, "nested compiler must be a module")
end
