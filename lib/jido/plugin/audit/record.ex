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

  @typedoc "A validated portable domain audit record."
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Validates one portable audit record."
  @spec validate(term()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = record) do
    with {:ok, record} <- Zoi.parse(@schema, Map.from_struct(record)),
         true <- Jido.Signal.ID.valid?(record.id) do
      case Jido.PortableTerm.validate(record, :record) do
        :ok -> {:ok, record}
        {:error, path} -> invalid("Audit record must contain portable data", %{path: path})
      end
    else
      false ->
        invalid("Audit record id must be a UUID7", %{id: record.id})

      {:error, _reason} = error ->
        error
    end
  end

  def validate(_record) do
    invalid("Expected an Audit Record", %{expected: __MODULE__})
  end

  defp invalid(message, details) do
    {:error, Jido.Error.validation_error(message, kind: :config, details: details)}
  end
end
