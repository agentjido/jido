defmodule Jido.Plugin.Spec do
  @moduledoc false

  @enforce_keys [:module, :options]
  defstruct module: nil,
            options: [],
            state_key: nil,
            state_schema: nil,
            directive_modules: [],
            dispatch?: false,
            runtime?: false

  @type t :: %__MODULE__{
          module: module(),
          options: keyword(),
          state_key: atom() | nil,
          state_schema: Zoi.schema() | nil,
          directive_modules: [module()],
          dispatch?: boolean(),
          runtime?: boolean()
        }
end
