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

  @doc false
  def new(kind, key) do
    with :ok <- reference_kind(kind),
         :ok <- reference_key(key),
         do: {:ok, %__MODULE__{kind: kind, key: key}}
  end

  @doc false
  def validate(%__MODULE__{kind: kind, key: key} = reference) do
    with {:ok, ^reference} <- new(kind, key), do: :ok
  end

  defp new!(kind, key) do
    case new(kind, key) do
      {:ok, value} -> value
      {:error, error} -> raise ArgumentError, Exception.message(error)
    end
  end

  @doc false
  def resolve(value, input, member \\ %{})

  def resolve(%__MODULE__{kind: kind, key: key}, input, member) do
    with {:ok, reference} <- new(kind, key) do
      source = if reference.kind == :input, do: input, else: member

      case Map.fetch(source, reference.key) do
        {:ok, value} -> {:ok, value}
        :error -> Authoring.error("Missing topology reference", %{kind: kind, key: key})
      end
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

  defp reference_kind(kind) when kind in [:input, :member], do: :ok
  defp reference_kind(_kind), do: Authoring.error("Reference kind must be :input or :member")

  defp reference_key(key) when is_atom(key) and key not in [nil, true, false], do: :ok

  defp reference_key(key) when is_binary(key) and byte_size(key) in 1..255 do
    if String.valid?(key), do: :ok, else: Authoring.error("Reference key must be UTF-8")
  end

  defp reference_key(_key),
    do: Authoring.error("Reference key must be a nonempty atom or string of at most 255 bytes")
end
