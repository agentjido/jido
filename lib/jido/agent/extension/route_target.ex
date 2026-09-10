defmodule Jido.Agent.Extension.RouteTarget do
  @moduledoc false

  @enforce_keys [:option, :value]
  defstruct [:extension, :option, :value]

  @type t :: %__MODULE__{
          extension: module() | nil,
          option: atom(),
          value: term()
        }
end
