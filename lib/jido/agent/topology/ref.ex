defmodule Jido.Agent.Topology.Ref do
  @moduledoc "A static reference to one public export of an included Agent topology."
  alias Jido.Agent.Authoring

  @enforce_keys [:component, :key]
  defstruct [:component, :key]

  @doc "Names an export. Nested components must re-export their public endpoints."
  def ref(component, key), do: %__MODULE__{component: key!(component), key: key!(key)}

  defp key!(key) do
    if Authoring.key?(key),
      do: Authoring.key_identity(key),
      else:
        raise(
          ArgumentError,
          "Export key must be a nonempty atom or UTF-8 string of at most 255 bytes"
        )
  end
end
