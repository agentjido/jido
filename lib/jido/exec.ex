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

  The run uses temporary supervised tasks that keep the caller's group leader.
  Set `:deadline_ms` to bound the whole call, or `:task_supervisor` to use a local
  host's admission limit. The default is `Jido.Exec.TaskSupervisor`.
  """
  @spec run(term(), map() | keyword() | nil, map() | keyword() | nil, keyword()) :: exec_result()
  def run(target, params \\ %{}, context \\ %{}, opts \\ []) do
    with {:ok, policy, limit, deadline, supervisor} <-
           Runtime.immediate_options(opts, default_max_concurrency()) do
      Runtime.run(supervisor, deadline, fn ->
        with {:ok, instruction} <- resolve(target, params, context) do
          span(instruction, supervisor, deadline, fn ->
            do_run_instruction(instruction, policy, limit, deadline)
          end)
        end
      end)
    end
  end

  defp resolve(target, params, context) do
    case Instruction.resolve(target, params, context) do
      {:ok, instruction} -> {:ok, instruction}
      {:error, error} -> {:error, Result.normalize(error)}
    end
  end

  defp span(%Instruction{kind: :flow} = instruction, supervisor, deadline, work) do
    Telemetry.span(:flow, Telemetry.flow_metadata(instruction), fn ->
      Runtime.run(supervisor, deadline, work)
    end)
  end

  defp span(%Instruction{}, _supervisor, _deadline, work), do: work.()

  defp reject_waits(workflow), do: Jido.Exec.Node.Wait.validate_host(workflow)

  defp do_run_instruction(%Instruction{} = instruction, policy, limit, deadline) do
    with {:ok, workflow, parallel?} <- Compiler.compile_for_run(instruction, []),
         :ok <- reject_waits(workflow) do
      concurrency = if parallel? and limit > 1, do: {:graph, limit}, else: {:component, limit}
      {workflow, observation} = run_workflow(workflow, instruction, policy, concurrency, deadline)
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

  defp run_workflow(workflow, instruction, policy, concurrency, deadline) do
    {react_opts, component_limit} =
      case concurrency do
        {:graph, limit} -> {[async: true, max_concurrency: limit], 1}
        {:component, limit} -> {[], limit}
      end

    context =
      instruction.context
      |> Runtime.caller_context()
      |> Runtime.inherit_tool_recorder()
      |> Map.put(:__jido_exec_max_concurrency__, component_limit)

    opts = [
      runnable_order: &Result.runnable_order/1,
      scheduler_policies: [{:default, Map.from_struct(policy)}]
    ]

    Runtime.quiet_failure_log()

    workflow
    |> Workflow.enable_event_emission()
    |> Workflow.put_run_context(%{_global: context})
    |> Workflow.execute(
      Jido.Exec.Fact.local_value(instruction.params),
      opts ++ react_opts ++ Runtime.deadline_options(deadline)
    )
  end

  defp default_max_concurrency do
    Application.get_env(
      :jido,
      :max_concurrency,
      min(System.schedulers_online(), @default_max_concurrency_ceiling)
    )
  end
end
