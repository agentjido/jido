defimpl Runic.Identity.Projectable, for: Jido.AI.Context do
  def identity_document(context), do: Jido.AI.Context.Snapshot.identity_document(context)
end
