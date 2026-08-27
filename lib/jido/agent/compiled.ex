defmodule Jido.Agent.Compiled do
  @moduledoc """
  Derived executable data for one canonical Agent definition.

  Build this value with `Jido.Agent.compile/2`. It is not author data and it
  must not be encoded or persisted.
  """

  @type source_path :: [String.t() | atom() | non_neg_integer()]
  @type source_location :: %{
          optional(:file) => String.t(),
          optional(:line) => pos_integer(),
          optional(:column) => pos_integer()
        }
  @type source_map :: %{optional(source_path()) => source_location()}

  @type t :: %__MODULE__{
          agent: Jido.Agent.t(),
          state_schema: Jido.Action.schema(),
          plugin_instances: [Jido.Plugin.Instance.t()],
          plugin_specs: [Jido.Plugin.Spec.t()],
          action_index: %{optional(module()) => map()},
          capability_index: %{optional(atom()) => [atom()]},
          routes: [Jido.Signal.Router.Route.t()],
          schedules: [map()],
          extension_plans: %{optional(module()) => term()},
          semantic_identity: map(),
          source_map: source_map()
        }

  @enforce_keys [
    :agent,
    :state_schema,
    :plugin_instances,
    :plugin_specs,
    :action_index,
    :capability_index,
    :routes,
    :schedules,
    :extension_plans,
    :semantic_identity,
    :source_map
  ]

  defstruct @enforce_keys
end
