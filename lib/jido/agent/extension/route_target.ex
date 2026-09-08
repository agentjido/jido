defmodule Jido.Agent.Extension.RouteTarget do
  @moduledoc "A static route target owned by one Agent authoring extension."

  @enforce_keys [:option, :value]
  defstruct [:extension, :option, :value]

  @type t :: %__MODULE__{
          extension: module() | nil,
          option: atom(),
          value: term()
        }
end
