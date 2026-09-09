defmodule Jido.Agent.Plugin.Transition do
  @moduledoc """
  Bounded result view for one Agent Plugin contribution callback.

  The before and after maps contain only declared Agent domain fields. The
  Directive list contains only types owned by this Plugin package.
  """

  alias Jido.Error

  @schema Zoi.struct(
            __MODULE__,
            %{
              plugin: Zoi.module(),
              agent_id: Zoi.string(),
              agent_module: Zoi.module(),
              before_state: Zoi.map(),
              after_state: Zoi.map(),
              plugin_state: Zoi.any() |> Zoi.optional(),
              input: Zoi.any() |> Zoi.optional(),
              source_signal: Zoi.struct(Jido.Signal),
              effective_signal: Zoi.struct(Jido.Signal),
              directives: Zoi.list(Zoi.any()) |> Zoi.default([])
            },
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the static schema for an Agent Plugin transition."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Validates an Agent Plugin transition."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def validate(%__MODULE__{} = transition) do
    case Zoi.parse(@schema, transition) do
      {:ok, validated} -> {:ok, validated}
      {:error, issues} -> invalid("Agent Plugin transition is invalid", %{issues: issues})
    end
  end

  def validate(value),
    do: invalid("Expected a Jido.Agent.Plugin.Transition value", %{value: value})

  defp invalid(message, details) do
    {:error,
     Error.validation_error(message,
       kind: :input,
       subject: __MODULE__,
       details: details
     )}
  end
end
