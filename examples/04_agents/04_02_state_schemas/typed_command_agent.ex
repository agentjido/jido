defmodule Jido.Examples.TypedCommandAgent do
  @moduledoc """
  An Agent with typed commands and complete candidate-state validation.

  The schema owns the count bounds. Actions do not repeat that check.
  An invalid candidate returns `Jido.Error.ValidationError` with code `:invalid_state`.
  The profile route supplies a default patch. A Signal patch replaces that
  entire nested map before the Action validates its input.
  """

  alias Jido.Joi

  defmodule Contract do
    def schema do
      Joi.object(%{
        count: Joi.integer() |> Joi.default(0),
        minimum: Joi.integer() |> Joi.default(0),
        maximum: Joi.integer() |> Joi.default(5),
        profile:
          Joi.object(%{name: Joi.string(), email: Joi.boolean(), push: Joi.boolean()})
          |> Joi.default(%{name: "Initial", email: true, push: false})
      })
      |> Joi.refine({__MODULE__, :within_bounds, []})
    end

    def within_bounds(%{count: count, minimum: minimum, maximum: maximum}, _opts) do
      if minimum <= count and count <= maximum,
        do: :ok,
        else: {:error, "count must be within ordered bounds"}
    end
  end

  use Jido.Agent, name: "basic_sdk_typed_commands"

  state do
    schema Contract.schema()
  end

  routes do
    signal_source "/examples/basic/typed_command_agent"

    route "basic.typed_command.patch_profile",
      as: :patch_profile,
      defaults: %{patch: %{name: "Route default", push: true}} do
      action %{patch: patch},
        schema:
          Joi.object(%{
            patch:
              Joi.object(
                %{name: Joi.string() |> Joi.optional(), push: Joi.boolean() |> Joi.optional()},
                unrecognized_keys: :error
              )
          }),
        context: context do
        profile = Map.merge(context.agent_state.profile, patch)
        profile = %{profile | name: String.trim(profile.name)}
        {:ok, %{context.agent_state | profile: profile}}
      end
    end

    route "basic.typed_command.set_count", as: :set_count do
      action %{count: count},
        schema: Joi.object(%{count: Joi.integer()}),
        context: context do
        # Complete Agent validation owns this bound check.
        {:ok, %{context.agent_state | count: count}}
      end
    end
  end
end
