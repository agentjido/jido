defmodule Jido.Agent.Topology.Reference do
  @moduledoc """
  A static reference in Agent composition declarations.

  `state/1` names a field of the owning Agent's state for initial composition.
  It records intent only. It does not read state, create children, or subscribe
  the child set to later state changes.
  """
  @enforce_keys [:kind, :key]
  defstruct [:kind, :key]

  @doc "Names the enclosing Agent as a topology endpoint."
  def root, do: %__MODULE__{kind: :root, key: nil}

  @doc false
  defdelegate key?(key), to: Jido.Agent.Authoring

  @doc "References one Agent state field for the initial composition snapshot."
  def state(key), do: new(:state, key)

  @doc "References one explicitly mapped composition input field."
  def input(key), do: new(:input, key)

  @doc "References one field of a keyed group member."
  def member(key), do: new(:member, key)

  defp new(kind, key) do
    if key?(key),
      do: %__MODULE__{kind: kind, key: key},
      else:
        raise(
          ArgumentError,
          "Reference key must be a nonempty atom or string of at most 255 bytes"
        )
  end
end
