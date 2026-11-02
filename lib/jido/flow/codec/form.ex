defmodule Jido.Flow.Codec.Form do
  @moduledoc false

  alias Jido.Authoring.Registry
  alias Jido.Flow.{Call, Error}
  alias Jido.Flow.Codec.{Data, Forms}

  @doc false
  @spec encode(Jido.Flow.Form.t(), Registry.t()) :: {:ok, map()} | {:error, Exception.t()}
  def encode(%Call{} = call, registry) do
    with {:ok, call} <- Data.encode_call(call, registry) do
      {:ok, Map.put(call, "type", "call")}
    end
  end

  def encode(form, registry) do
    case Forms.encode(form, registry) do
      {:ok, {tag, payload}} ->
        with :ok <- reserved_fields(payload), do: {:ok, Map.put(payload, "type", tag)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc false
  @spec decode(term(), Registry.t(), list()) ::
          {:ok, map()} | {:error, [Exception.t()]}
  def decode(%{"type" => "call"} = record, registry, path) do
    with :ok <- Data.exact_fields(record, ["type" | Data.call_fields()], path) do
      record
      |> Map.delete("type")
      |> Data.decode_call(registry, path)
    end
  end

  def decode(%{"type" => type} = record, registry, path) when is_binary(type) do
    Forms.decode(type, Map.delete(record, "type"), registry, path)
  end

  def decode(%{} = record, _registry, path) when not is_struct(record),
    do: Data.failure("stored Flow form type is required", path, :form)

  def decode(_record, _registry, path),
    do: Data.failure("stored Flow form must be a map", path, :form)

  defp reserved_fields(payload) when is_map(payload) and not is_struct(payload) do
    if Map.has_key?(payload, "type") do
      {:error,
       Error.validation_error("Flow form Codec returned a reserved field", %{
         reason: :form_codec
       })}
    else
      :ok
    end
  end

  defp reserved_fields(_payload),
    do:
      {:error,
       Error.validation_error("Flow form Codec must return a map", %{
         reason: :form_codec
       })}
end
