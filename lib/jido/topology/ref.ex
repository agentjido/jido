defmodule Jido.Topology.Ref do
  @moduledoc "A reference to one public export of an included topology."
  alias Jido.Agent.Authoring

  @schema Zoi.struct(__MODULE__, %{component: Zoi.string(), key: Zoi.string()}, coerce: true)
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the export reference schema."
  def schema, do: @schema

  @doc "Names a public export. Nested components must re-export their public endpoints."
  def ref(component, key) do
    case new(component, key) do
      {:ok, value} -> value
      {:error, error} -> raise error
    end
  end

  @doc false
  def new(component, key) do
    with {:ok, component} <- Jido.Topology.Validation.key(component),
         {:ok, key} <- Jido.Topology.Validation.key(key),
         do: {:ok, %__MODULE__{component: component, key: key}}
  end

  @doc false
  def target(%__MODULE__{component: component, key: key}), do: new(component, key)
  def target(value) when is_struct(value), do: Authoring.error("Invalid topology endpoint")
  def target(value), do: Jido.Topology.Validation.key(value)
end
