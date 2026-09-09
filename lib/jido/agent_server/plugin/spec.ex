defmodule Jido.AgentServer.Plugin.Spec do
  @moduledoc false

  @enforce_keys [:package, :module, :options]
  defstruct package: nil,
            module: nil,
            options: [],
            dispatch?: false,
            runtime?: false,
            legacy?: false

  @type t :: %__MODULE__{
          package: module(),
          module: module(),
          options: keyword(),
          dispatch?: boolean(),
          runtime?: boolean(),
          legacy?: boolean()
        }
end
