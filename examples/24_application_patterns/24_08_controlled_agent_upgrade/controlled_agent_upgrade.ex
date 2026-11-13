defmodule Jido.Examples.Patterns.ControlledUpgrade.AccountV1 do
  use Jido.Agent, name: "example_controlled_upgrade_account", vsn: 1

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/controlled-upgrade/v1"

    route "examples.controlled_upgrade.increment", as: :increment do
      action _input, context: context do
        {:ok, %{count: context.agent_state.count + 1}}
      end
    end
  end
end

defmodule Jido.Examples.Patterns.ControlledUpgrade.AccountV2 do
  use Jido.Agent, name: "example_controlled_upgrade_account", vsn: 2

  state do
    schema Jido.Joi.object(%{
             total: Jido.Joi.integer(),
             currency: Jido.Joi.string()
           })
  end

  routes do
    signal_source "/examples/controlled-upgrade/v2"

    route "examples.controlled_upgrade.increment", as: :increment do
      action _input, context: context do
        {:ok, %{context.agent_state | total: context.agent_state.total + 1}}
      end
    end
  end
end

defmodule Jido.Examples.Patterns.ControlledUpgrade.AccountRollbackV3 do
  use Jido.Agent, name: "example_controlled_upgrade_account", vsn: 3

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/controlled-upgrade/v3"

    route "examples.controlled_upgrade.increment", as: :increment do
      action _input, context: context do
        {:ok, %{count: context.agent_state.count + 1}}
      end
    end
  end
end

defmodule Jido.Examples.Patterns.ControlledUpgrade.ToV2 do
  use Jido.Action, name: "example_controlled_upgrade_to_v2"

  @impl true
  def run(%{snapshot: %{agent: %{vsn: 1, state: %{count: count}}} = snapshot}, _context) do
    definition = Jido.Examples.Patterns.ControlledUpgrade.AccountV2.definition()

    replacement =
      definition
      |> Map.put(:module, snapshot.agent.module)
      |> Jido.Agent.instantiate!(
        id: snapshot.agent.id,
        state: %{total: count, currency: "USD"}
      )

    with {:ok, snapshot} <- Jido.Persistence.snapshot(replacement),
         do: {:ok, %{snapshot: snapshot}}
  end

  def run(_params, _context),
    do: {:error, Jido.Error.validation_error("expected an Account V1 snapshot")}
end

defmodule Jido.Examples.Patterns.ControlledUpgrade.RollbackToV1Shape do
  use Jido.Action, name: "example_controlled_upgrade_rollback_to_v1_shape"

  @impl true
  def run(%{snapshot: %{agent: %{vsn: 2, state: %{total: total}}} = snapshot}, _context) do
    definition = Jido.Examples.Patterns.ControlledUpgrade.AccountRollbackV3.definition()

    replacement =
      definition
      |> Map.put(:module, snapshot.agent.module)
      |> Jido.Agent.instantiate!(id: snapshot.agent.id, state: %{count: total})

    with {:ok, snapshot} <- Jido.Persistence.snapshot(replacement),
         do: {:ok, %{snapshot: snapshot}}
  end

  def run(_params, _context),
    do: {:error, Jido.Error.validation_error("expected an Account V2 snapshot")}
end

defmodule Jido.Examples.Patterns.ControlledUpgrade.FailUpgrade do
  use Jido.Action, name: "example_controlled_upgrade_failure"

  @impl true
  def run(_params, _context),
    do: {:error, Jido.Error.execution_error("injected migration failure")}
end
