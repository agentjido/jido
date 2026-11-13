defmodule Jido.Examples.EffectfulSteps do
  @moduledoc "Synchronous effects and transient clients in one Agent Turn."
  use Jido.Agent, name: "workflow_effectful_agent"

  state do
    schema Jido.Joi.object(%{
             key: Jido.Joi.string() |> Jido.Joi.default(""),
             result: Jido.Joi.map() |> Jido.Joi.default(%{})
           })
  end

  routes do
    signal_source "/workflow"

    route "workflow.effects", Jido.Examples.EffectfulSteps.Pipeline,
      as: :fetch_record,
      defaults: %{allowed: true, expected_revision: "r1"} do
    end
  end
end

defmodule Jido.Examples.EffectfulSteps.Read do
  @moduledoc false

  use Jido.Action,
    name: "workflow_effect_read",
    schema:
      Jido.Joi.object(%{
        key: Jido.Joi.string() |> Jido.Joi.min(1),
        allowed: Jido.Joi.boolean(),
        expected_revision: Jido.Joi.string()
      })

  @impl true
  def run(%{key: key}, %{agent_state: %{key: key} = state}) do
    {:ok, %{key: key, record: state.result, cached: true}}
  end

  def run(input, context) do
    case context[:service] do
      {module, client} ->
        case module.call(client, :read, %{key: input.key}) do
          {:ok, record} ->
            {:ok, Map.merge(input, %{record: record, cached: false})}

          {:error, reason} ->
            {:error,
             Jido.Error.execution_error("read failed",
               reason: reason,
               retry: reason == :unavailable
             )}
        end

      _ ->
        {:error, Jido.Error.validation_error("service context required", field: :service)}
    end
  end
end

defmodule Jido.Examples.EffectfulSteps.Pipeline do
  @moduledoc "Guards an external read and selects the state that can commit."

  use Jido.Flow,
    name: "workflow_effects",
    schema:
      Jido.Joi.object(%{
        key: Jido.Joi.string() |> Jido.Joi.min(1),
        allowed: Jido.Joi.boolean(),
        expected_revision: Jido.Joi.string()
      }),
    output_schema: Jido.Joi.object(%{key: Jido.Joi.string() |> Jido.Joi.min(1), result: Jido.Joi.map()})

  flow do
    step "guard", params <- input() do
      if params.allowed,
        do: {:ok, params},
        else: {:error, Jido.Error.validation_error("request denied", stage: :guard)}
    end

    step "read", action: Jido.Examples.EffectfulSteps.Read, params: result("guard")

    step "project", input <- result("read") do
      cond do
        input.cached ->
          {:ok, %{key: input.key, result: input.record}}

        input.record.revision == input.expected_revision ->
          # Select portable output before the Agent commits it.
          {:ok, %{key: input.key, result: Map.take(input.record, [:revision, :answer])}}

        true ->
          {:error, Jido.Error.validation_error("source revision is stale", stage: :project)}
      end
    end

    output result("project")
  end
end
