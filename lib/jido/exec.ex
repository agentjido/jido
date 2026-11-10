defmodule Jido.Exec do
  @moduledoc """
  Compiles and runs Jido Actions and Flows with Runic.

  One Action is compiled as a one-node Runic Workflow. A Flow is compiled as
  a larger Runic Workflow. Runic owns runnable preparation, execution policy,
  graph updates, and checkpoints.

  Use `run/4` for immediate execution. It returns `{:ok, output}`,
  `{:ok, output, effects}`, or `{:error, error}`. A terminal Handoff can return
  `{:handoff, successor_instruction, effects}`. Effects are returned to the
  caller without dispatch. See [Execution](execution.md).

  Use `compile/2` when you need direct Runic execution. The compiled
  `Runic.Workflow` can run through `Runic.Runner` for stepwise execution,
  inspection, or custom recovery policy. Use `result/1,2` to project a
  completed Runic workflow to the Jido result contract.
  """

  alias Jido.Exec.{Compiler, Frame, Runtime}
  alias Jido.Telemetry.Exec, as: Telemetry
  alias Jido.Instruction
  alias Runic.Workflow

  alias Runic.Workflow.{
    Execution,
    ExecutionUncertain,
    Fact,
    RunnableDispatched,
    RunnableFailed,
    SchedulerPolicy
  }

  @default_task_supervisor Jido.Exec.TaskSupervisor
  @default_max_concurrency_ceiling 10

  @typedoc "A local Task Supervisor PID, registered name, or via reference."
  @type task_supervisor :: pid() | atom() | {:via, module(), term()}

  @type exec_result ::
          {:ok, term()}
          | {:ok, term(), [term()]}
          | {:handoff, Instruction.t(), [term()]}
          | {:error, Exception.t() | term()}

  @typedoc "A capability supplied by the current execution host."
  @type capability :: :waits

  @doc "Returns true when an Action context supports the specified host capability."
  @spec supports?(map(), capability()) :: boolean()
  def supports?(%{jido_exec_capabilities: capabilities}, capability)
      when is_list(capabilities),
      do: not List.improper?(capabilities) and capability in capabilities

  def supports?(context, _capability) when is_map(context), do: false

  @doc "Compiles an Action, Instruction, Flow module, or Flow value to Runic."
  @spec compile(term(), keyword()) :: {:ok, Workflow.t()} | {:error, Exception.t()}
  def compile(target, opts \\ []), do: Compiler.compile(target, opts)

  @doc "Compiles an executable target to Runic or raises its error."
  @spec compile!(term(), keyword()) :: Workflow.t() | no_return()
  def compile!(target, opts \\ []), do: Compiler.compile!(target, opts)

  @doc "Derives a stable identity for one deferred effect in a completed Runic output."
  @spec effect_id(term(), Runic.Identity.t(), Runic.Identity.t(), non_neg_integer()) ::
          Runic.Identity.t()
  def effect_id(execution_id, activation_id, output_id, index)
      when is_integer(index) and index >= 0 do
    Runic.Identity.digest(:event_data, %{
      kind: :jido_effect,
      version: 1,
      execution_id: execution_id,
      activation_id: activation_id,
      output_id: output_id,
      index: index
    })
  end

  @doc """
  Runs an Action or Flow to completion with the in-memory Runic runtime.

  `Jido.Exec.run/4` runs the Action or Flow in a supervised task.
  The complete execution runs in an unlinked temporary task under
  `Jido.Exec.TaskSupervisor`. The task keeps the caller's group leader. Pass
  `task_supervisor: reference` to use another local Task Supervisor.
  """
  @spec run(term(), map() | keyword() | nil, map() | keyword() | nil, keyword()) :: exec_result()
  def run(target, params \\ %{}, context \\ %{}, opts \\ []) do
    group_leader = Process.group_leader()

    with {:ok, task_supervisor, execution_opts} <- run_options(opts),
         {:ok, instruction} <- resolve(target, params, context) do
      span(instruction, fn ->
        Jido.Exec.Runtime.run(task_supervisor, group_leader, fn ->
          do_run_instruction(instruction, execution_opts)
        end)
      end)
    end
  end

  defp resolve(target, params, context) do
    case Instruction.resolve(target, params, context) do
      {:ok, instruction} -> {:ok, instruction}
      {:error, error} -> {:error, normalize_runtime_error(error)}
    end
  end

  defp span(%Instruction{kind: :flow} = instruction, work),
    do: Telemetry.span(:flow, Telemetry.flow_metadata(instruction), work)

  defp span(%Instruction{}, work), do: work.()

  defp reject_waits(workflow), do: Jido.Exec.Node.Wait.validate_host(workflow)

  defp do_run_instruction(instruction, opts) do
    with {:ok, instruction} <- validate_flow_input(instruction),
         {:ok, workflow} <- compile(instruction),
         :ok <- reject_waits(workflow),
         {:ok, workflow, observation} <-
           run_workflow(
             workflow,
             execution_input(instruction),
             instruction.context,
             instruction.kind,
             opts
           ) do
      result(workflow, observation)
    else
      {:error, error} -> {:error, normalize_runtime_error(error)}
    end
  end

  @doc """
  Projects a Runic workflow to the `run/4` result contract.

  This snapshot form includes historical failures and uncertain work. Use it
  for a completed restored workflow. A missing Flow or Action result returns
  an error.
  """
  @spec result(Workflow.t()) :: exec_result()
  def result(%Workflow{} = workflow), do: project_result(workflow, result_error(workflow), nil)

  @doc """
  Projects a Runic execution observation.

  With a workflow and observation from `Runic.Workflow.execute/3` or
  `Runic.Runner.execution/3`, selects that input occurrence. Active work,
  stopped admission, failures, and uncertain work return errors. Store
  acknowledgement remains a separate Runic persistence status.
  """
  @spec result(Workflow.t(), Execution.t()) :: exec_result()
  def result(%Workflow{} = workflow, %Execution{} = observation),
    do: project_result(workflow, result_error(observation, workflow), observation)

  defp incomplete_error(execution_id, reason),
    do:
      Jido.Error.execution_error("Exec execution is not complete", %{
        execution_id: execution_id,
        reason: reason,
        retry: false
      })

  defp run_workflow(workflow, input, context, kind, opts) do
    with {:ok, policy, react_opts} <- execution_options(opts, kind) do
      context =
        context
        |> Jido.Exec.Runtime.context()
        |> Map.put(:__jido_exec_max_concurrency__, Keyword.get(react_opts, :max_concurrency, 1))

      Runtime.quiet_failure_log()

      {workflow, observation} =
        workflow
        |> Workflow.enable_event_emission()
        |> Workflow.put_run_context(%{_global: context})
        |> Workflow.execute(
          Jido.Exec.Fact.local_value(input),
          Keyword.merge(react_opts,
            runnable_order: &observation_order/1,
            scheduler_policies: [{:default, Map.from_struct(policy)}]
          )
        )

      {:ok, workflow, observation}
    end
  end

  defp observation_order(runnable) do
    {elem(Runic.Workflow.Runnable.order_key(runnable), 0), Map.get(runnable.node, :name),
     map_item_index(runnable.input_fact), Runic.Workflow.Runnable.activation_id(runnable)}
  end

  defp failure_order(failure, workflow) do
    {depth, activation} = failure.order_key || {0, nil}

    index =
      case failure.error do
        %{details: %{item_index: index}} -> index
        _error -> failure_item_index(workflow, activation)
      end

    {depth, failure.node_name, index}
  end

  defp failure_item_index(workflow, activation) do
    Enum.find_value(workflow.runnable_events, 0, fn
      %RunnableDispatched{order_key: {_depth, ^activation}, input_fact: fact} ->
        map_item_index(fact)

      %ExecutionUncertain{members: members} ->
        Enum.find_value(members || [], fn
          %{order_key: {_depth, ^activation}, input_fact_id: id} ->
            map_item_index(Map.get(workflow.graph.vertices, id))

          _member ->
            nil
        end)

      _event ->
        nil
    end)
  end

  defp map_item_index(%Fact{} = fact) do
    case Jido.Exec.Fact.value(fact) do
      {:jido_map_item, index, _id, _params} -> index
      _value -> 0
    end
  end

  defp map_item_index(_fact), do: 0

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
        project(fact)

      {:error, reason} ->
        {:error, result_load_error(reason)}

      nil ->
        case result_fact(workflow, nil, resolver) do
          {:error, reason} ->
            {:error, result_load_error(reason)}

          result when not is_nil(observation) and not is_nil(result) ->
            {:error, incomplete_error(observation.id, :foreign_execution)}

          _missing ->
            project(nil)
        end
    end
  end

  defp project_result(_workflow, error, _observation, _resolver),
    do: {:error, normalize_runtime_error(error)}

  defp result_load_error(reason) do
    Jido.Error.execution_error("Exec result could not be loaded", %{
      phase: :rehydration,
      reason: reason
    })
  end

  defp project(%Fact{meta: meta} = fact) do
    value = Jido.Exec.Fact.value(fact)
    effects = get_in(meta, [:jido, :effects]) || []

    case {get_in(meta, [:jido, :control]), value} do
      {:handoff, %Instruction{} = instruction} ->
        {:handoff, instruction, effects}

      _ ->
        if effects == [], do: {:ok, value}, else: {:ok, value, effects}
    end
  end

  defp project(_missing),
    do: {:error, Jido.Error.execution_error("Exec produced no result")}

  # Snapshot compatibility for restored workflows without live observations.
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

  defp execution_options(opts, kind) when is_list(opts) do
    if Keyword.keyword?(opts) do
      allowed = [
        :timeout,
        :max_attempts,
        :backoff,
        :base_delay_ms,
        :max_delay_ms,
        :max_concurrency
      ]

      case Keyword.keys(opts) -- allowed do
        [] ->
          with {:ok, policy} <- build_policy(opts),
               {:ok, max_concurrency} <- max_concurrency(opts) do
            react_opts =
              if kind == :flow and max_concurrency > 1,
                do: [async: true, max_concurrency: max_concurrency],
                else: []

            {:ok, policy, react_opts}
          end

        unknown ->
          {:error, Jido.Error.config_error("unknown execution options", %{options: unknown})}
      end
    else
      {:error, Jido.Error.config_error("execution options must be a keyword list")}
    end
  end

  defp run_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.get_values(opts, :task_supervisor) do
        [] ->
          with :ok <- validate_task_supervisor(@default_task_supervisor) do
            {:ok, @default_task_supervisor, opts}
          end

        [task_supervisor] ->
          with :ok <- validate_task_supervisor(task_supervisor) do
            {:ok, task_supervisor, Keyword.delete(opts, :task_supervisor)}
          end

        _duplicates ->
          {:error,
           Jido.Error.config_error("pass only one task_supervisor reference", %{
             option: :task_supervisor,
             reason: :duplicate_option
           })}
      end
    else
      {:error, Jido.Error.config_error("execution options must be a keyword list")}
    end
  end

  defp run_options(_opts),
    do: {:error, Jido.Error.config_error("execution options must be a keyword list")}

  defp validate_task_supervisor(task_supervisor)
       when is_pid(task_supervisor) or
              (is_atom(task_supervisor) and task_supervisor not in [nil, true, false]) or
              (is_tuple(task_supervisor) and tuple_size(task_supervisor) == 3 and
                 elem(task_supervisor, 0) == :via) do
    case GenServer.whereis(task_supervisor) do
      pid when is_pid(pid) and node(pid) == node() ->
        if Process.alive?(pid), do: :ok, else: not_running(task_supervisor)

      _other ->
        not_running(task_supervisor)
    end
  rescue
    exception ->
      {:error,
       Jido.Error.config_error("Task Supervisor lookup failed", %{
         option: :task_supervisor,
         task_supervisor: task_supervisor,
         reason: exception
       })}
  catch
    kind, reason ->
      {:error,
       Jido.Error.config_error("Task Supervisor lookup failed", %{
         option: :task_supervisor,
         task_supervisor: task_supervisor,
         reason: {kind, reason}
       })}
  end

  defp validate_task_supervisor(task_supervisor) do
    {:error,
     Jido.Error.config_error(
       "task_supervisor must be a local PID, registered name, or {:via, module, name} reference",
       %{option: :task_supervisor, value: task_supervisor}
     )}
  end

  defp not_running(task_supervisor) do
    {:error,
     Jido.Error.config_error("Task Supervisor is not running", %{
       option: :task_supervisor,
       task_supervisor: task_supervisor
     })}
  end

  defp max_concurrency(opts) do
    case Keyword.get_lazy(opts, :max_concurrency, &default_max_concurrency/0) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value ->
        {:error,
         Jido.Error.config_error("max_concurrency must be a positive integer", %{
           option: :max_concurrency,
           value: value
         })}
    end
  end

  defp default_max_concurrency do
    Application.get_env(
      :jido,
      :max_concurrency,
      min(System.schedulers_online(), @default_max_concurrency_ceiling)
    )
  end

  defp build_policy(opts) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    max_attempts = Keyword.get(opts, :max_attempts, 1)
    backoff = Keyword.get(opts, :backoff, :none)
    base_delay_ms = Keyword.get(opts, :base_delay_ms, 0)
    max_delay_ms = Keyword.get(opts, :max_delay_ms, 0)

    cond do
      timeout != :infinity and not (is_integer(timeout) and timeout >= 0) ->
        {:error, Jido.Error.config_error("timeout must be non-negative or :infinity")}

      not (is_integer(max_attempts) and max_attempts >= 1) ->
        {:error, Jido.Error.config_error("max_attempts must be a positive integer")}

      backoff not in [:none, :linear, :exponential, :jitter] ->
        {:error, Jido.Error.config_error("invalid backoff policy")}

      not (is_integer(base_delay_ms) and base_delay_ms >= 0) ->
        {:error, Jido.Error.config_error("base_delay_ms must be non-negative")}

      not (is_integer(max_delay_ms) and max_delay_ms >= 0) ->
        {:error, Jido.Error.config_error("max_delay_ms must be non-negative")}

      true ->
        {:ok,
         %SchedulerPolicy{
           timeout_ms: timeout,
           max_retries: max_attempts - 1,
           backoff: backoff,
           base_delay_ms: base_delay_ms,
           max_delay_ms: max_delay_ms,
           on_failure: :halt,
           retry_if: {Jido.Error, :retryable?, []}
         }}
    end
  end

  defp normalize_runtime_error(error) when is_exception(error), do: error

  defp normalize_runtime_error({:timeout, timeout}) do
    Jido.Error.timeout_error("Action timed out", %{timeout: timeout})
  end

  defp normalize_runtime_error({:task_crashed, reason}) do
    Jido.Error.execution_error("Action process exited", %{
      phase: :execution_task,
      reason: reason
    })
  end

  defp normalize_runtime_error(reason) do
    Jido.Error.execution_error("Runic execution failed", %{reason: reason})
  end

  defp execution_input(%Instruction{kind: :action}), do: %{}
  defp execution_input(%Instruction{kind: :flow, params: params}), do: Frame.new(params)

  defp validate_flow_input(instruction), do: Jido.Exec.Runtime.flow_input(instruction)
end
