defmodule Jido.Examples.PortableValues do
  @moduledoc "Validates data before it crosses a storage or recovery boundary."

  alias Jido.Codec.Term

  def validate(value), do: Term.validate(value, :agent_state)
  def portable?(value), do: Term.valid?(value)
end
