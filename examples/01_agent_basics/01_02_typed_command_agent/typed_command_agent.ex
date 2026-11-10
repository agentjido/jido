defmodule Jido.Examples.TypedCommandAgent do
  @moduledoc """
  An Agent with typed commands and complete candidate-state validation.

  The schema owns the count bounds. Actions do not repeat that check.
  An invalid candidate returns `Jido.Error.ValidationError` with code `:invalid_state`.
  The profile route supplies a default patch. A Signal patch replaces that
  entire nested map before the Action validates its input.
  """

  defmodule Contract do
    def schema do
      Jido.Joi.object(%{
        count: Jido.Joi.integer() |> Jido.Joi.default(0),
        minimum: Jido.Joi.integer() |> Jido.Joi.default(0),
        maximum: Jido.Joi.integer() |> Jido.Joi.default(5),
        profile:
          Jido.Joi.object(%{name: Jido.Joi.string(), email: Jido.Joi.boolean(), push: Jido.Joi.boolean()})
          |> Jido.Joi.default(%{name: "Initial", email: true, push: false})
      })
      |> Jido.Joi.refine({__MODULE__, :within_bounds, []})
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
          Jido.Joi.object(%{
            patch:
              Jido.Joi.object(
                %{name: Jido.Joi.string() |> Jido.Joi.optional(), push: Jido.Joi.boolean() |> Jido.Joi.optional()},
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
        schema: Jido.Joi.object(%{count: Jido.Joi.integer()}),
        context: context do
        # Complete Agent validation owns this bound check.
        {:ok, %{context.agent_state | count: count}}
      end
    end
  end
end
