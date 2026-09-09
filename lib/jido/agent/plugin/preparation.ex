defmodule Jido.Agent.Plugin.Preparation do
  @moduledoc """
  Bounded input and result for one Agent Plugin preparation callback.

  `agent_state` contains only fields declared by `observes/1`. `plugin_state`
  contains only the state value owned by this Plugin package. The callback can
  replace `effective_signal`, `context`, and `input`. All other fields are read
  only.
  """

  alias Jido.Error

  @schema Zoi.struct(
            __MODULE__,
            %{
              plugin: Zoi.module(description: "Plugin package module"),
              agent_id: Zoi.string(description: "Agent identifier"),
              agent_module: Zoi.module(description: "Agent definition module"),
              agent_state:
                Zoi.map(description: "Declared Agent domain-state projection")
                |> Zoi.default(%{}),
              plugin_state: Zoi.any(description: "Current owned Plugin state") |> Zoi.optional(),
              source_signal: Zoi.struct(Jido.Signal, description: "Unchanged source Signal"),
              effective_signal: Zoi.struct(Jido.Signal, description: "Current effective Signal"),
              context: Zoi.map(description: "Transient caller context") |> Zoi.default(%{}),
              input: Zoi.any(description: "Owned prepared Plugin input") |> Zoi.optional()
            },
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the static schema for Agent Plugin preparation data."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Validates one Agent Plugin preparation value."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def validate(%__MODULE__{} = preparation) do
    case Zoi.parse(@schema, preparation) do
      {:ok, validated} -> {:ok, validated}
      {:error, issues} -> invalid("Agent Plugin preparation is invalid", %{issues: issues})
    end
  end

  def validate(value),
    do: invalid("Expected a Jido.Agent.Plugin.Preparation value", %{value: value})

  defp invalid(message, details) do
    {:error,
     Error.validation_error(message,
       kind: :input,
       subject: __MODULE__,
       details: details
     )}
  end
end
