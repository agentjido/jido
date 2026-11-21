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
  def project(%Workflow{} = workflow, %Execution{} = observation) do
    if in_workflow?(observation, workflow) do
      project_result(workflow, result_error(observation, workflow), observation.input_fact_id)
    else
      {:error, incomplete_error(observation.id, :foreign_execution)}
    end
  end

  defp in_workflow?(observation, workflow) do
    vertices = workflow.graph.vertices

    # An explicit execution ID can give different workflows the same input Fact ID.
    Map.has_key?(vertices, observation.input_fact_id) and
      Enum.all?(observation.outcomes, fn outcome ->
        Map.has_key?(vertices, outcome.node_hash) and recorded_fact?(outcome, vertices)
      end) and
      Enum.all?(observation.ready, &Map.has_key?(vertices, &1.node_hash))
  end

  defp recorded_fact?(%{result: %Fact{hash: hash, payload_digest: digest, meta: meta}}, vertices),
    do: match?(%{payload_digest: ^digest, meta: ^meta}, Map.get(vertices, hash))

  defp recorded_fact?(_outcome, _vertices), do: true

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

  defp result_fact(workflow, nil), do: Workflow.results(workflow, nil, facts: true)[:result]

  defp result_fact(workflow, input_fact_id) do
    case Workflow.results(workflow, nil, facts: true, all: true) do
      %{result: facts} when is_list(facts) ->
        Enum.find(facts, &(Workflow.root_ancestor_hash(workflow, &1) == input_fact_id))

      _ports ->
        nil
    end
  end

  defp project_result(workflow, nil, input_fact_id),
    do: project_fact(result_fact(workflow, input_fact_id))

  defp project_result(_workflow, error, _input_fact_id), do: {:error, normalize(error)}

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
