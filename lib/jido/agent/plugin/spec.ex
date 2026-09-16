defmodule Jido.Agent.Plugin.Spec do
  @moduledoc false

  @enforce_keys [:package, :module, :options]
  defstruct package: nil,
            module: nil,
            options: [],
            state_key: nil,
            state_schema: nil,
            directive_modules: []

  @type t :: %__MODULE__{
          package: module(),
          module: module(),
          options: keyword(),
          state_key: atom() | nil,
          state_schema: Zoi.schema() | nil,
          directive_modules: [module()]
        }
end
