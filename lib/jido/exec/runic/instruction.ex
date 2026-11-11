defimpl Runic.Identity.Projectable, for: Jido.Instruction do
  def identity_document(instruction) do
    %{
      kind: :jido_instruction,
      version: 1,
      target: target_identity(instruction.target),
      target_kind: instruction.kind,
      params: instruction.params,
      context: instruction.context,
      metadata: instruction.metadata
    }
  end

  defp target_identity(%Jido.Flow{} = flow), do: Jido.Flow.Identity.semantic_digest(flow)
  defp target_identity(module), do: module
end
