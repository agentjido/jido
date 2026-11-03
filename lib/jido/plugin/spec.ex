defmodule Jido.Plugin.Spec do
  @moduledoc false

  defmodule Agent do
    @moduledoc false

    @enforce_keys [:package, :module, :options]
    defstruct package: nil,
              module: nil,
              options: [],
              state_key: nil,
              state_schema: nil,
              directive_modules: [],
              route_selector?: false

    @type t :: %__MODULE__{
            package: module(),
            module: module(),
            options: keyword(),
            state_key: atom() | nil,
            state_schema: Jido.Joi.schema() | nil,
            directive_modules: [module()],
            route_selector?: boolean()
          }
  end

  defmodule Runtime do
    @moduledoc false

    @enforce_keys [:package, :module, :options]
    defstruct package: nil,
              module: nil,
              options: [],
              dispatch?: false,
              runtime?: false

    @type t :: %__MODULE__{
            package: module(),
            module: module(),
            options: keyword(),
            dispatch?: boolean(),
            runtime?: boolean()
          }
  end

  defmodule Persistence do
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

  @enforce_keys [:module, :options]
  defstruct module: nil,
            options: [],
            manifest: nil,
            agent: nil,
            agent_server: nil,
            persistence: nil

  @type t :: %__MODULE__{
          module: module(),
          options: keyword(),
          manifest: Jido.Plugin.Manifest.t(),
          agent: Agent.t() | nil,
          agent_server: Runtime.t() | nil,
          persistence: Persistence.t() | nil
        }
end
