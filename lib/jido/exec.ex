defmodule Jido.Exec do
  @moduledoc """
  Compiles and runs Jido Actions and Flows with Runic.

  One Action is lowered to its canonical one-step Flow. Actions and authored
  Flows then use the same Runic compilation and execution path. Runic owns
  runnable preparation, execution policy, graph updates, and checkpoints.

  Use `run/4` for immediate execution. It returns `{:ok, output}`,
  `{:ok, output, effects}`, or `{:error, error}`. A terminal Handoff can return
  `{:handoff, successor_instruction, effects}`. Effects are returned to the
  caller without dispatch. See [Execution](execution.md).

  Use `compile/2` when you need direct Runic execution. The compiled
  `Runic.Workflow` can run through `Runic.Runner` for stepwise execution,
  inspection, or custom recovery policy. Use `result/2` to project one Runic
  execution observation to the Jido result contract. Direct Runic use is an
  advanced escape hatch, not a second Jido execution API.
  """

  alias Jido.Exec.{Compiler, Result, Runtime}
  alias Jido.Telemetry.Exec, as: Telemetry
  alias Jido.Instruction
  alias Runic.Workflow

  alias Runic.Workflow.Execution

  @default_task_supervisor Jido.Exec.TaskSupervisor
  @default_max_concurrency_ceiling 10

  @type exec_result ::
          {:ok, term()}
          | {:ok, term(), [term()]}
          | {:handoff, Instruction.t(), [term()]}
          | {:error, Exception.t() | term()}

  @typedoc "A capability supplied by the current execution host."
  @type capability :: :waits

  @doc "Returns true when an Action context supports the specified host capability."
  @spec supports?(map(), capability()) :: boolean()
  def supports?(%{jido_exec_capabilities: capabilities}, :waits)
      when is_list(capabilities),
      do: not List.improper?(capabilities) and :waits in capabilities

  def supports?(context, _capability) when is_map(context), do: false

  @doc "Compiles an Action, Instruction, Flow module, or Flow value to Runic."
  @spec compile(term(), keyword()) :: {:ok, Workflow.t()} | {:error, Exception.t()}
  def compile(target, opts), do: Compiler.compile(target, opts)

  @doc """
  Runs an Action or Flow to completion with the in-memory Runic runtime.

  `Jido.Exec.run/4` runs the Action or Flow in a supervised task.
  The complete execution runs in an unlinked temporary task under
  `Jido.Exec.TaskSupervisor`. The task keeps the caller's group leader.
  """
  @spec run(term(), map() | keyword() | nil, map() | keyword() | nil, keyword()) :: exec_result()
  def run(target, params \\ %{}, context \\ %{}, opts \\ []) do
    group_leader = Process.group_leader()

    with {:ok, instruction} <-
           Jido.Exec.Runtime.run(@default_task_supervisor, group_leader, fn ->
             resolve(target, params, context)
           end) do
      span(instruction, fn ->
        Jido.Exec.Runtime.run(@default_task_supervisor, group_leader, fn ->
          do_run_instruction(instruction, opts)
        end)
      end)
    end
  end

  defp resolve(target, params, context) do
    case Instruction.resolve(target, params, context) do
      {:ok, instruction} -> {:ok, instruction}
      {:error, error} -> {:error, Result.normalize(error)}
    end
  end

  defp span(%Instruction{kind: :flow} = instruction, work),
    do: Telemetry.span(:flow, Telemetry.flow_metadata(instruction), work)

  defp span(%Instruction{}, work), do: work.()

  defp reject_waits(workflow), do: Jido.Exec.Node.Wait.validate_host(workflow)

  defp do_run_instruction(%Instruction{} = instruction, opts) do
    with {:ok, workflow, parallel?} <- Compiler.compile_for_run(instruction, []),
         :ok <- reject_waits(workflow),
         {:ok, workflow, observation} <-
           run_workflow(
             workflow,
             execution_input(instruction),
             instruction.context,
             opts,
             parallel?
           ) do
      result(workflow, observation)
    else
      {:error, error} -> {:error, Result.normalize(error)}
    end
  end

  @doc """
  Projects a Runic execution observation.

  With a workflow and observation from `Runic.Workflow.execute/3` or
  `Runic.Runner.execution/3`, selects that input occurrence. Active work,
  stopped admission, foreign observations, failures, and uncertain work return
  errors. Store acknowledgement remains a separate Runic persistence status.
  """
  @spec result(Workflow.t(), Execution.t()) :: exec_result()
  def result(%Workflow{} = workflow, %Execution{} = observation),
    do: Result.project(workflow, observation)

  defp run_workflow(workflow, input, context, opts, parallel?) do
    with {:ok, policy, max_concurrency} <-
           Runtime.execution_options(opts, max_concurrency: default_max_concurrency()) do
      runic_concurrency? = max_concurrency > 1 and parallel?

      react_opts =
        if runic_concurrency?,
          do: [async: true, max_concurrency: max_concurrency],
          else: []

      component_max_concurrency = if runic_concurrency?, do: 1, else: max_concurrency

      context =
        context
        |> Jido.Exec.Runtime.caller_context()
        |> Map.put(:__jido_exec_max_concurrency__, component_max_concurrency)

      Runtime.quiet_failure_log()

      {workflow, observation} =
        workflow
        |> Workflow.enable_event_emission()
        |> Workflow.put_run_context(%{_global: context})
        |> Workflow.execute(
          Jido.Exec.Fact.local_value(input),
          Keyword.merge(react_opts,
            runnable_order: &Result.runnable_order/1,
            scheduler_policies: [{:default, Map.from_struct(policy)}]
          )
        )

      {:ok, workflow, observation}
    end
  end

  defp default_max_concurrency do
    Application.get_env(
      :jido,
      :max_concurrency,
      min(System.schedulers_online(), @default_max_concurrency_ceiling)
    )
  end

  defp execution_input(%Instruction{params: params}), do: params
end
