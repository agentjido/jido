defimpl Runic.Transmutable, for: Jido.Instruction do
  alias Jido.Exec.Compiler
  alias Jido.Exec.Node.Action
  alias Jido.Instruction

  def transmute(instruction), do: to_workflow(instruction)

  def to_workflow(%Instruction{kind: :action} = instruction) do
    instruction
    |> Action.new()
    |> Runic.Transmutable.to_workflow()
  end

  def to_workflow(%Instruction{kind: :flow} = instruction) do
    Compiler.compile!(instruction)
  end

  def to_component(%Instruction{kind: :action} = instruction), do: Action.new(instruction)

  def to_component(%Instruction{kind: :flow}) do
    raise ArgumentError, "a Flow Instruction compiles to a Runic Workflow, not one component"
  end
end
