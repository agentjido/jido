defmodule Jido.Agent.Plugin.Contribution do
  @moduledoc """
  State and Directive contribution from one Agent Plugin facet.

  `state` is `:unchanged` or `{:replace, complete_owned_state}`. `directives`
  can contain only Directive types owned by the same Plugin package.
  """

  alias Jido.Error

  @enforce_keys [:plugin]
  defstruct plugin: nil, state: :unchanged, directives: []

  @type state_change :: :unchanged | {:replace, term()}
  @type t :: %__MODULE__{
          plugin: module(),
          state: state_change(),
          directives: [struct()]
        }

  @doc "Validates the common contribution shape."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def validate(%__MODULE__{plugin: plugin, state: state, directives: directives} = contribution)
      when is_atom(plugin) and not is_nil(plugin) and is_list(directives) do
    if (state == :unchanged or match?({:replace, _value}, state)) and
         Enum.all?(directives, &is_struct/1) do
      {:ok, contribution}
    else
      invalid("Agent Plugin contribution is invalid", %{
        state: state,
        directives: directives
      })
    end
  end

  def validate(value),
    do: invalid("Expected a Jido.Agent.Plugin.Contribution value", %{value: value})

  defp invalid(message, details) do
    {:error,
     Error.validation_error(message,
       kind: :input,
       subject: __MODULE__,
       details: details
     )}
  end
end
