defimpl Jido.Codec.Encoder, for: Jido.Agent do
  def codec(_agent), do: {:ok, Jido.Agent.Codec}
end
