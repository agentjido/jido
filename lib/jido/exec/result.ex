defmodule Jido.Exec.Result do
  @moduledoc false

  alias Jido.Instruction
  alias Runic.Workflow

  alias Runic.Workflow.{
    Execution,
    ExecutionUncertain,
    Fact,
    RunnableFailed
  }

  @doc false
  @spec project(Workflow.t()) :: Jido.Exec.exec_result()
  def project(%Workflow{} = workflow), do: project_result(workflow, result_error(workflow), nil)

  @doc false
  @spec project(Workflow.t(), Execution.t()) :: Jido.Exec.exec_result()
  def project(%Workflow{} = workflow, %Execution{} = observation),
    do: project_result(workflow, result_error(observation, workflow), observation)

  @doc false
  def runnable_order(runnable) do
    {elem(Runic.Workflow.Runnable.order_key(runnable), 0), Map.get(runnable.node, :name),
     Runic.Workflow.Runnable.activation_id(runnable)}
  end

  @doc false
  def normalize(error) when is_exception(error), do: error

  def normalize({:timeout, timeout}) do
    Jido.Error.timeout_error("Action timed out", %{timeout: timeout})
  end

  def normalize({:task_crashed, reason}) do
    Jido.Error.execution_error("Action process exited", %{
      phase: :execution_task,
      reason: reason
    })
  end

  def normalize(reason) do
    Jido.Error.execution_error("Runic execution failed", %{reason: reason})
  end

  defp incomplete_error(execution_id, reason) do
    Jido.Error.execution_error("Exec execution is not complete", %{
      execution_id: execution_id,
      reason: reason,
      retry: false
    })
  end

  defp failure_order(failure, workflow) do
    {depth, activation} = failure.order_key || {0, nil}
    {depth, failure.node_name, activation, workflow.name}
  end

  defp result_fact(workflow, nil, resolver) do
    case Workflow.results(workflow, nil, facts: true) do
      %{result: fact} -> resolve_result_fact(fact, resolver)
      _ports -> nil
    end
  end

  defp result_fact(workflow, input_fact_id, resolver) do
    case Workflow.results(workflow, nil, facts: true, all: true) do
      %{result: facts} when is_list(facts) ->
        facts
        |> Enum.find(&(Workflow.root_ancestor_hash(workflow, &1) == input_fact_id))
        |> resolve_result_fact(resolver)

      _ports ->
        nil
    end
  end

  defp resolve_result_fact(%Fact{} = fact, _resolver), do: fact

  defp resolve_result_fact(
         %Runic.Workflow.FactRef{} = fact,
         %Runic.Workflow.FactResolver{} = resolver
       ) do
    case Runic.Workflow.FactResolver.resolve(fact, resolver) do
      {:ok, fact} -> fact
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_result_fact(_fact, _resolver), do: nil

  defp project_result(workflow, error, observation),
    do: project_result(workflow, error, observation, nil)

  defp project_result(workflow, nil, observation, resolver) do
    fact = result_fact(workflow, if(observation, do: observation.input_fact_id), resolver)

    case fact do
      %Fact{} ->
        project_fact(fact)

      {:error, reason} ->
        {:error, result_load_error(reason)}

      nil ->
        case result_fact(workflow, nil, resolver) do
          {:error, reason} ->
            {:error, result_load_error(reason)}

          result when not is_nil(observation) and not is_nil(result) ->
            {:error, incomplete_error(observation.id, :foreign_execution)}

          _missing ->
            project_fact(nil)
        end
    end
  end

  defp project_result(_workflow, error, _observation, _resolver),
    do: {:error, normalize(error)}

  defp result_load_error(reason) do
    Jido.Error.execution_error("Exec result could not be loaded", %{
      phase: :rehydration,
      reason: reason
    })
  end

  defp project_fact(%Fact{meta: meta} = fact) do
    value = Jido.Exec.Fact.value(fact)
    effects = get_in(meta, [:jido, :effects]) || []

    case {get_in(meta, [:jido, :control]), value} do
      {:handoff, %Instruction{} = instruction} ->
        {:handoff, instruction, effects}

      _ ->
        if effects == [], do: {:ok, value}, else: {:ok, value, effects}
    end
  end

  defp project_fact(_missing),
    do: {:error, Jido.Error.execution_error("Exec produced no result")}

  # Restored workflows have no live execution observation.
  defp result_error(%Workflow{runnable_events: events} = workflow) do
    events
    |> Enum.flat_map(fn
      %RunnableFailed{error: nil} ->
        []

      %RunnableFailed{} = event ->
        node = Map.get(workflow.graph.vertices, event.node_hash, %{})

        [
          %{
            kind: :failed,
            error: event.error,
            order_key: event.order_key,
            node_name: Map.get(node, :name, event.node_hash)
          }
        ]

      %ExecutionUncertain{} = event ->
        member = Enum.min_by(event.members || [], & &1.order_key, fn -> %{} end)

        [
          %{
            kind: :uncertain,
            error: event.reason,
            order_key: event.order_key,
            node_name: Map.get(member, :node_name)
          }
        ]

      _event ->
        []
    end)
    |> result_error(workflow)
  end

  defp result_error(%Execution{quiescent?: false, id: id}, _workflow),
    do: incomplete_error(id, :execution_active)

  defp result_error(%Execution{} = observation, workflow) do
    case result_error(Execution.failures(observation), workflow) do
      nil when observation.admission == :stopped ->
        incomplete_error(observation.id, :admission_stopped)

      error ->
        error
    end
  end

  defp result_error(failures, workflow) when is_list(failures) do
    failure =
      failures
      |> Enum.reject(&(&1.kind == :skipped and is_nil(&1.error)))
      |> Enum.min_by(&failure_order(&1, workflow), fn -> nil end)

    case failure do
      %{kind: :uncertain, error: reason} ->
        uncertain_error(reason)

      %{error: error} ->
        error

      nil ->
        nil
    end
  end

  defp uncertain_error(reason) do
    Jido.Error.execution_error("Runic execution outcome is uncertain", %{
      phase: :execution_task,
      outcome: :uncertain,
      reason: reason,
      retry: false
    })
  end
end
