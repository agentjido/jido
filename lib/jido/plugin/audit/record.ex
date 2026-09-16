defmodule Jido.Plugin.Audit.Record do
  @moduledoc "One portable domain audit record."

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Stable audit record identifier"),
              at: Zoi.integer(description: "Record time in Unix milliseconds") |> Zoi.min(0),
              event: Zoi.any(description: "Domain event"),
              outcome: Zoi.atom(description: "Domain outcome"),
              metadata: Zoi.map(description: "Portable record metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Validates one portable audit record."
  def validate(%__MODULE__{} = record) do
    with {:ok, record} <- Zoi.parse(@schema, Map.from_struct(record)),
         true <- Jido.Signal.ID.valid?(record.id),
         :ok <- Jido.Action.validate_static_data(record) do
      {:ok, record}
    else
      false ->
        invalid("Audit record id must be a UUID7", %{id: record.id})

      {:error, reason} when is_binary(reason) ->
        invalid("Audit record must contain portable data", %{reason: reason})

      {:error, _reason} = error ->
        error
    end
  end

  defp invalid(message, details) do
    {:error, Jido.Error.validation_error(message, kind: :config, details: details)}
  end
end
