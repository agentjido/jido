defmodule Jido.Plugin.Audit.Record do
  alias Jido.Joi
  @moduledoc "One portable domain audit record."

  @schema Joi.struct(
            __MODULE__,
            %{
              id: Joi.string(description: "Stable audit record identifier"),
              at: Joi.integer(description: "Record time in Unix milliseconds") |> Joi.min(0),
              event: Joi.any(description: "Domain event"),
              outcome: Joi.atom(description: "Domain outcome"),
              metadata: Joi.map(description: "Portable record metadata") |> Joi.default(%{})
            },
            coerce: true
          )

  @typedoc "A validated portable domain audit record."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Joi.schema()
  def schema, do: @schema

  @doc "Validates one portable audit record."
  @spec validate(term()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = record) do
    with {:ok, record} <- Joi.parse(@schema, Map.from_struct(record)),
         true <- Jido.Id.uuid7?(record.id) do
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
