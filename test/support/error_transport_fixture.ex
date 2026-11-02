defmodule JidoTest.ErrorTransport.UnrenderableError do
  defexception [:message_failure, :inspect_failure]

  @impl true
  def message(%__MODULE__{message_failure: failure}), do: fail(failure)

  def fail(:raise), do: raise("message failure")
  def fail(:throw), do: throw(:message_failure)
  def fail(:exit), do: exit(:message_failure)
  def fail(_failure), do: "unrenderable error"
end

defimpl Inspect, for: JidoTest.ErrorTransport.UnrenderableError do
  alias JidoTest.ErrorTransport.UnrenderableError

  def inspect(%{inspect_failure: failure}, _options), do: UnrenderableError.fail(failure)
end
