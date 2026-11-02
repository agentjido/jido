defmodule Jido.Flow.FieldError do
  @moduledoc false

  @enforce_keys [:errors]
  defstruct [:errors]
  @type t :: %__MODULE__{errors: [Exception.t()]}

  @doc false
  @spec new([Exception.t()]) :: t()
  def new(errors) do
    errors =
      Enum.map(errors, fn error ->
        path = Map.get(error.details, :path, [])
        %{error | details: error.details |> Map.put(:source_path, path) |> Map.put(:path, [])}
      end)

    %__MODULE__{errors: errors}
  end
end
