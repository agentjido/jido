defmodule Jido.Agent.Plugin.Spec do
  @moduledoc false

  @enforce_keys [:package, :module, :options]
  defstruct package: nil,
            module: nil,
            options: [],
            state_key: nil,
            state_schema: nil,
            observations: [],
            directive_modules: [],
            legacy?: false

  @type t :: %__MODULE__{
          package: module(),
          module: module(),
          options: keyword(),
          state_key: atom() | nil,
          state_schema: Zoi.schema() | nil,
          observations: [atom()],
          directive_modules: [module()],
          legacy?: boolean()
        }
end
