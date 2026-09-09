defmodule Jido.Examples.TypedCommandAgent do
  @moduledoc """
  An Agent with typed commands and complete candidate-state validation.

  The schema owns the count bounds. Actions do not repeat that check.
  The profile route supplies a default patch. A Signal patch replaces that
  entire nested map before the Action validates its input.
  """

  defmodule Contract do
    def schema do
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.default(0),
        minimum: Zoi.integer() |> Zoi.default(0),
        maximum: Zoi.integer() |> Zoi.default(5),
        profile:
          Zoi.object(%{name: Zoi.string(), email: Zoi.boolean(), push: Zoi.boolean()})
          |> Zoi.default(%{name: "Initial", email: true, push: false})
      })
      |> Zoi.refine({__MODULE__, :within_bounds, []})
    end

    def within_bounds(%{count: count, minimum: minimum, maximum: maximum}, _opts) do
      if minimum <= count and count <= maximum,
        do: :ok,
        else: {:error, "count must be within ordered bounds"}
    end
  end

  use Jido.Agent, name: "basic_sdk_typed_commands"

  agent do
    schema Contract.schema()
  end

  routes do
    signal_source "/examples/basic/typed_command_agent"

    route "basic.typed_command.patch_profile" do
      action %{patch: patch},
        schema:
          Zoi.object(%{
            patch:
              Zoi.object(
                %{name: Zoi.string() |> Zoi.optional(), push: Zoi.boolean() |> Zoi.optional()},
                unrecognized_keys: :error
              )
          }),
        context: context do
        profile = Map.merge(context.agent_state.profile, patch)
        profile = %{profile | name: String.trim(profile.name)}
        {:ok, %{context.agent_state | profile: profile}}
      end

      defaults %{patch: %{name: "Route default", push: true}}
      define :patch_profile, args: [{:optional, :patch}]
    end

    route "basic.typed_command.set_count" do
      action %{count: count},
        schema: Zoi.object(%{count: Zoi.integer()}),
        context: context do
        # Complete Agent validation owns this bound check.
        {:ok, %{context.agent_state | count: count}}
      end

      define :set_count, args: [:count]
    end
  end
end
