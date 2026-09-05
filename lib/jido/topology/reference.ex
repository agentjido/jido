defmodule Jido.Topology.Reference do
  @moduledoc "Static references to topology input or a keyed group member."

  alias Jido.Agent.Authoring

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum([:input, :member]),
              key: Zoi.union([Zoi.atom(), Zoi.string()])
            },
            coerce: true
          )
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the reference schema."
  def schema, do: @schema

  @doc "References one topology input field."
  def input(key), do: new!(:input, key)

  @doc "References one field of a keyed group member."
  def member(key), do: new!(:member, key)

  defp new!(kind, key) do
    case Zoi.parse(@schema, %{kind: kind, key: key}) do
      {:ok, value} -> value
      {:error, _} -> raise ArgumentError, "Reference key must be an atom or string"
    end
  end

  @doc false
  def resolve(value, input, member \\ %{})

  def resolve(%__MODULE__{kind: kind, key: key}, input, member) do
    source = if kind == :input, do: input, else: member

    case Map.fetch(source, key) do
      {:ok, value} -> {:ok, value}
      :error -> Authoring.error("Missing topology reference", %{kind: kind, key: key})
    end
  end

  def resolve(value, input, member) when is_map(value) and not is_struct(value) do
    with {:ok, pairs} <-
           Authoring.traverse(Enum.to_list(value), fn {key, value} ->
             with {:ok, value} <- resolve(value, input, member), do: {:ok, {key, value}}
           end),
         do: {:ok, Map.new(pairs)}
  end

  def resolve(value, input, member) when is_list(value),
    do: Authoring.traverse(value, &resolve(&1, input, member))

  def resolve(value, input, member) when is_tuple(value) do
    with {:ok, values} <- resolve(Tuple.to_list(value), input, member),
         do: {:ok, List.to_tuple(values)}
  end

  def resolve(value, _input, _member), do: {:ok, value}
end
