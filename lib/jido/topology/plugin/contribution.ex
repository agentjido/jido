defmodule Jido.Topology.Plugin.Contribution do
  @moduledoc """
  Static canonical entries returned by one Topology Plugin facet.

  The current contract accepts Bus resources, ownership relationships, and Bus
  subscriptions. Bus is the first core resource type. A contribution cannot
  add Agent definitions or another resource type.
  """

  alias Jido.Error

  @enforce_keys [:plugin]
  defstruct plugin: nil, resources: [], relationships: [], connections: []

  @type t :: %__MODULE__{
          plugin: module(),
          resources: [map()],
          relationships: [map()],
          connections: [map()]
        }

  @doc "Validates the common contribution shape."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def validate(%__MODULE__{} = contribution) do
    if is_atom(contribution.plugin) and not is_nil(contribution.plugin) and
         Enum.all?(
           [contribution.resources, contribution.relationships, contribution.connections],
           &is_list/1
         ) do
      {:ok, contribution}
    else
      invalid("Topology Plugin contribution is invalid", %{contribution: contribution})
    end
  end

  def validate(value),
    do: invalid("Expected a Jido.Topology.Plugin.Contribution value", %{value: value})

  defp invalid(message, details) do
    {:error,
     Error.validation_error(message,
       kind: :input,
       subject: __MODULE__,
       details: details
     )}
  end
end
