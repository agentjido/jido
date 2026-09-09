defmodule Jido.Topology.Plugin.Spec do
  @moduledoc false

  @enforce_keys [:package, :module, :options, :vsn]
  defstruct [:package, :module, :options, :vsn]

  @type t :: %__MODULE__{
          package: module(),
          module: module(),
          options: keyword(),
          vsn: pos_integer()
        }
end
