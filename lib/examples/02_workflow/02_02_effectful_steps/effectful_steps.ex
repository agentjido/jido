defmodule Jido.Examples.EffectfulSteps.Read do
  @moduledoc false
  use Jido.Action, name: "workflow_effect_read"

  def run(%{key: key}, %{agent_state: %{key: key} = state}) do
    {:ok, %{key: key, record: state.result, cached: true}}
  end

  def run(input, context) do
    Jido.Examples.Workflow.Observation.record(context, :read, input)

    case context[:service] do
      {module, client} ->
        case module.call(client, :read, %{key: input.key}) do
          {:ok, record} ->
            {:ok, Map.merge(input, %{record: record, cached: false})}

          {:error, reason} ->
            {:error, Jido.Action.Error.execution_error("read failed", reason: reason)}
        end

      _ ->
        {:error, Jido.Action.Error.validation_error("service context required", field: :service)}
    end
  end
end

defmodule Jido.Examples.EffectfulSteps.Project do
  @moduledoc false
  use Jido.Action, name: "workflow_effect_project"
  def run(%{cached: true} = input, _context), do: {:ok, %{key: input.key, result: input.record}}

  def run(input, context) do
    Jido.Examples.Workflow.Observation.record(context, :project, input.record)

    if input.record.revision == input.expected_revision do
      # The application explicitly selects portable output. Jido does not redact it.
      {:ok, %{key: input.key, result: Map.take(input.record, [:revision, :answer])}}
    else
      {:error, Jido.Action.Error.validation_error("source revision is stale", stage: :project)}
    end
  end
end

defmodule Jido.Examples.EffectfulSteps.Pipeline do
  @moduledoc "Guards an external read and selects the state that can commit."
  alias Jido.Examples.Workflow.Observation

  use Jido.Flow,
    name: "workflow_effects",
    schema:
      Zoi.object(%{
        key: Zoi.string() |> Zoi.min(1),
        allowed: Zoi.boolean(),
        expected_revision: Zoi.string()
      })

  flow do
    step "guard" do
      action params <- input(), context: ctx do
        Observation.record(ctx, :guard, params)

        if params.allowed,
          do: {:ok, params},
          else: {:error, Jido.Action.Error.validation_error("request denied", stage: :guard)}
      end
    end

    step "read", action: Jido.Examples.EffectfulSteps.Read, params: result("guard")
    step "project", action: Jido.Examples.EffectfulSteps.Project, params: result("read")
    output result("project")
  end
end

defmodule Jido.Examples.EffectfulSteps do
  @moduledoc "Synchronous effects and transient clients in one Agent Turn."
  use Jido.Agent, name: "workflow_effectful_agent"

  agent do
    schema Zoi.object(%{
             key: Zoi.string() |> Zoi.default(""),
             result: Zoi.map() |> Zoi.default(%{})
           })
  end

  routes do
    signal_source "/workflow"

    route "workflow.effects", Jido.Examples.EffectfulSteps.Pipeline do
      defaults %{allowed: true, expected_revision: "r1"}
      define :fetch_record, args: [:key, {:optional, :allowed}, {:optional, :expected_revision}]
    end
  end
end
