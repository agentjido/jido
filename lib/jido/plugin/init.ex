defmodule Jido.Plugin.Init do
  alias Jido.Joi

  @moduledoc """
  Input for one supervised Agent Plugin runtime generation.

  `plugin_state` is the validated value selected from this Plugin's owned field
  in the complete Agent state map. It is a runtime bootstrap view, not a second
  stored state map. It is paired with `state_version` when the Agent Server
  builds the value. A replacement runtime gets a new Init value from the latest
  complete commit. Runtime handles and the complete Agent are not part of this
  value.

  Use `Jido.Plugin.state/2` when a running resource must read state after a
  later commit.
  """

  @schema Joi.struct(
            __MODULE__,
            %{
              agent_server: Joi.pid(description: "Owning Agent Server process"),
              agent_id: Joi.string(description: "Owning Agent identifier"),
              module: Joi.module(description: "Plugin module"),
              plugin_state:
                Joi.any(description: "Immutable value of the Plugin-owned Agent field")
                |> Joi.optional(),
              state_version:
                Joi.integer(description: "Agent state version paired with the owned value")
                |> Joi.min(0)
                |> Joi.default(0),
              jido: Joi.atom(description: "Optional Jido instance") |> Joi.optional(),
              partition: Joi.any(description: "Optional Agent partition") |> Joi.optional(),
              options:
                Joi.list(
                  Joi.tuple({Joi.atom(), Joi.any()}),
                  description: "Plugin options"
                )
                |> Joi.default([])
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc "Returns the data schema for Plugin runtime initialization."
  @spec schema() :: Joi.schema()
  def schema, do: @schema
end
