defmodule Jido.Codec.Reference do
  @moduledoc "Encodes and decodes JSON-safe references to Catalog entries."

  alias Jido.Catalog
  alias Jido.Catalog.Error

  @spec encode(Catalog.t(), Catalog.Entry.kind() | [Catalog.Entry.kind()], term()) ::
          {:ok, %{required(String.t()) => term()}} | {:error, Error.t()}
  def encode(%Catalog{} = catalog, kinds, target) do
    with {:ok, {id, vsn}} <- Catalog.reference(catalog, kinds, target),
         do: {:ok, %{"id" => id, "vsn" => vsn}}
  end

  @spec decode(Catalog.t(), term(), Catalog.Entry.kind() | [Catalog.Entry.kind()]) ::
          {:ok, term()} | {:error, Error.t()}
  def decode(%Catalog{} = catalog, document, kinds) do
    with {:ok, reference} <- parse(document),
         do: Catalog.resolve(catalog, reference, kinds)
  end

  @spec parse(term()) :: {:ok, Catalog.key()} | {:error, Error.t()}
  def parse(%{"id" => id, "vsn" => vsn} = reference) when map_size(reference) == 2,
    do: Catalog.validate_reference({id, vsn})

  def parse(%{} = reference) when not is_struct(reference) do
    fields = Map.keys(reference)

    field =
      case Enum.sort(fields -- ["id", "vsn"]) do
        [unknown | _rest] -> unknown
        [] -> if("id" in fields, do: "vsn", else: "id")
      end

    error("Catalog reference must contain only id and vsn", %{field: field})
  end

  def parse(_reference),
    do: error("Catalog reference must contain only id and vsn")

  defp error(message, details \\ %{}),
    do: {:error, Error.exception(message: message, details: details)}
end
