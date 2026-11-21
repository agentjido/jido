defmodule Jido.Statechart.Error do
  @moduledoc "Errors for the public Statechart API."

  defmodule InvalidChart do
    @moduledoc "Invalid XML or a chart outside the supported SCXML profile."
    use Splode.Error, fields: [:reason], class: :invalid

    @type t :: %__MODULE__{reason: String.t()}

    @impl Exception
    def message(%{reason: reason}), do: "Invalid SCXML chart: " <> reason
  end
end
