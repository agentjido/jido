defmodule Jido.Examples.TypedCommandAgent do
  @moduledoc """
  A typed command Agent that tests SDK validation boundaries.

  The schema owns the count bounds. Actions do not repeat that check.
  The duplicate route and invalid count input exercise rejection paths.
  Caller context supplies the observer. Messages expose Action entry; they do not change Agent state.
  The profile route supplies a default patch. A Signal patch replaces that
  entire nested map before the Action validates its input.
  Unknown and duplicate routes both return Jido.Error.RoutingError before
  Action execution. The integration test checks direct and live execution.
  """

  alias Jido.Examples.DirectiveAgent.{Effects, Record}

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

  defmodule OwnedState do
    use Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(0)}
  end

  defmodule Patch do
    use Jido.Action,
      name: "basic_sdk_patch",
      schema:
        Zoi.object(%{
          patch:
            Zoi.object(
              %{name: Zoi.string() |> Zoi.optional(), push: Zoi.boolean() |> Zoi.optional()},
              unrecognized_keys: :error
            )
        })

    @impl true
    def run(input, %{agent_state: state, observer: observer}) do
      send(observer, {:sdk_action, :patch})
      profile = Map.merge(state.profile, input.patch)
      {:ok, %{state | profile: %{profile | name: String.trim(profile.name)}}}
    end
  end

  defmodule SetCount do
    use Jido.Action,
      name: "basic_sdk_set_count",
      schema: Zoi.object(%{count: Zoi.integer()})

    @impl true
    def run(input, %{agent_state: state, observer: observer}) do
      send(observer, {:sdk_action, :set_count})
      # Deliberately omit the domain bound check. Final SDK validation must
      # reject a correctly typed candidate that violates the root refinement.
      {:ok, %{state | count: input.count}, [%Record{label: "count accepted"}]}
    end
  end

  use Jido.Agent, name: "basic_sdk_typed_commands"

  agent do
    schema Contract.schema()
    plugin Effects
  end

  routes do
    signal_source "/examples/basic/typed_command_agent"

    route "basic.profile.patch", Patch do
      defaults %{patch: %{name: "Route default", push: true}}
      define :patch_profile, args: [{:optional, :patch}]
    end

    route "basic.count.set", SetCount do
      define :set_count, args: [:count]
    end

    route "basic.ambiguous", Patch
    route "basic.ambiguous", SetCount
  end
end
