defmodule Jido.Exec do
  @moduledoc """
  Exec provides a robust set of methods for executing Actions (`Jido.Action`).

  This module offers functionality to:
  - Run actions synchronously or asynchronously
  - Manage timeouts and retries
  - Cancel running actions
  - Normalize and validate input parameters and context
  - Emit telemetry events for monitoring and debugging

  Execs are defined as modules (Actions) that implement specific callbacks, allowing for
  a standardized way of defining and executing complex actions across a distributed system.

  ## Features

  - Synchronous and asynchronous action execution
  - Automatic retries with exponential backoff
  - Timeout handling for long-running actions
  - Parameter and context normalization
  - Comprehensive error handling and reporting
  - Telemetry integration for monitoring and tracing
  - Cancellation of running actions

  ## Usage

  Execs are executed using the `run/4` or `run_async/4` functions:

      Jido.Exec.run(MyAction, %{param1: "value"}, %{context_key: "context_value"})

  See `Jido.Action` for how to define an Action.

  For asynchronous execution:

      async_ref = Jido.Exec.run_async(MyAction, params, context)
      # ... do other work ...
      result = Jido.Exec.await(async_ref)

  """

  use Private
  use ExDbug, enabled: false

  alias Jido.Error
  alias Jido.Instruction

  require Logger
  require OK

  import Jido.Util, only: [cond_log: 3]

  @default_timeout 5000
  @default_max_retries 1
  @initial_backoff 250

  @type action :: module()
  @type params :: map()
  @type context :: map()
  @type run_opts :: [timeout: non_neg_integer()]
  @type async_ref :: %{ref: reference(), pid: pid()}

  @doc """
  Executes a Action synchronously with the given parameters and context.

  ## Parameters

  - `action`: The module implementing the Action behavior.
  - `params`: A map of input parameters for the Action.
  - `context`: A map providing additional context for the Action execution.
  - `opts`: Options controlling the execution:
    - `:timeout` - Maximum time (in ms) allowed for the Action to complete (default: #{@default_timeout}).
    - `:max_retries` - Maximum number of retry attempts (default: #{@default_max_retries}).
    - `:backoff` - Initial backoff time in milliseconds, doubles with each retry (default: #{@initial_backoff}).
    - `:log_level` - Override the global Logger level for this specific action. Accepts #{inspect(Logger.levels())}.

  ## Action Metadata in Context

  The action's metadata (name, description, category, tags, version, etc.) is made available
  to the action's `run/2` function via the `context` parameter under the `:action_metadata` key.
  This allows actions to access their own metadata when needed.

  ## Returns

  - `{:ok, result}` if the Action executes successfully.
  - `{:error, reason}` if an error occurs during execution.

  ## Examples

      iex> Jido.Exec.run(MyAction, %{input: "value"}, %{user_id: 123})
      {:ok, %{result: "processed value"}}

      iex> Jido.Exec.run(MyAction, %{invalid: "input"}, %{}, timeout: 1000)
      {:error, %Jido.Error{type: :validation_error, message: "Invalid input"}}

      iex> Jido.Exec.run(MyAction, %{input: "value"}, %{}, log_level: :debug)
      {:ok, %{result: "processed value"}}

      # Access action metadata in the action:
      # defmodule MyAction do
      #   use Jido.Action,
      #     name: "my_action",
      #     description: "Example action",
      #     vsn: "1.0.0"
      #
      #   def run(_params, context) do
      #     metadata = context.action_metadata
      #     {:ok, %{name: metadata.name, version: metadata.vsn}}
      #   end
      # end
  """
  @spec run(action(), params(), context(), run_opts()) :: {:ok, map()} | {:error, Error.t()}
  def run(action, params \\ %{}, context \\ %{}, opts \\ [])

  def run(action, params, context, opts) when is_atom(action) and is_list(opts) do
    dbug("Starting action run", action: action, params: params, context: context, opts: opts)
    log_level = Keyword.get(opts, :log_level, :info)

    with {:ok, normalized_params} <- normalize_params(params),
         {:ok, normalized_context} <- normalize_context(context),
         :ok <- validate_action(action),
         OK.success(validated_params) <- validate_params(action, normalized_params) do
      enhanced_context =
        Map.put(normalized_context, :action_metadata, action.__action_metadata__())

      dbug("Params and context normalized and validated",
        normalized_params: normalized_params,
        normalized_context: enhanced_context,
        validated_params: validated_params
      )

      cond_log(
        log_level,
        :notice,
        "Executing #{inspect(action)} with params: #{inspect(validated_params)} and context: #{inspect(enhanced_context)}"
      )

      do_run_with_retry(action, validated_params, enhanced_context, opts)
    else
      {:error, reason} ->
        dbug("Error in action setup", error: reason)
        cond_log(log_level, :debug, "Action Execution failed: #{inspect(reason)}")
        OK.failure(reason)

      {:error, reason, other} ->
        dbug("Error with additional info in action setup", error: reason, other: other)
        cond_log(log_level, :debug, "Action Execution failed with directive: #{inspect(reason)}")
        {:error, reason, other}
    end
  rescue
    e in [FunctionClauseError, BadArityError, BadFunctionError] ->
      log_level = Keyword.get(opts, :log_level, :info)
      dbug("Function error in action", error: e)

      cond_log(
        log_level,
        :warning,
        "Function invocation error in action: #{Exception.message(e)}"
      )

      OK.failure(Error.invalid_action("Invalid action module: #{Exception.message(e)}"))

    e ->
      log_level = Keyword.get(opts, :log_level, :info)
      dbug("Unexpected error in action", error: e)
      cond_log(log_level, :error, "Unexpected error in action: #{Exception.message(e)}")

      OK.failure(
        Error.internal_server_error("An unexpected error occurred: #{Exception.message(e)}")
      )
  catch
    kind, reason ->
      log_level = Keyword.get(opts, :log_level, :info)
      dbug("Caught error in action", kind: kind, reason: reason)

      cond_log(
        log_level,
        :warning,
        "Caught unexpected throw/exit in action: #{Exception.message(reason)}"
      )

      OK.failure(Error.internal_server_error("Caught #{kind}: #{inspect(reason)}"))
  end

  def run(%Instruction{} = instruction, _params, _context, _opts) do
    dbug("Running instruction", instruction: instruction)

    run(
      instruction.action,
      instruction.params,
      instruction.context,
      instruction.opts
    )
  end

  def run(action, _params, _context, _opts) do
    dbug("Invalid action type", action: action)
    OK.failure(Error.invalid_action("Expected action to be a module, got: #{inspect(action)}"))
  end

  @doc """
  Executes a Action asynchronously with the given parameters and context.

  This function immediately returns a reference that can be used to await the result
  or cancel the action.

  **Note**: This approach integrates with OTP by spawning tasks under a `Task.Supervisor`.
  Make sure `{Task.Supervisor, name: Jido.TaskSupervisor}` is part of your supervision tree.

  ## Parameters

  - `action`: The module implementing the Action behavior.
  - `params`: A map of input parameters for the Action.
  - `context`: A map providing additional context for the Action execution.
  - `opts`: Options controlling the execution (same as `run/4`).

  ## Returns

  An `async_ref` map containing:
  - `:ref` - A unique reference for this async action.
  - `:pid` - The PID of the process executing the Action.

  ## Examples

      iex> async_ref = Jido.Exec.run_async(MyAction, %{input: "value"}, %{user_id: 123})
      %{ref: #Reference<0.1234.5678>, pid: #PID<0.234.0>}

      iex> result = Jido.Exec.await(async_ref)
      {:ok, %{result: "processed value"}}
  """
  @spec run_async(action(), params(), context(), run_opts()) :: async_ref()
  def run_async(action, params \\ %{}, context \\ %{}, opts \\ []) do
    dbug("Starting async action", action: action, params: params, context: context, opts: opts)
    ref = make_ref()
    parent = self()

    # Start the task under the TaskSupervisor.
    # If the supervisor is not running, this will raise an error.
    {:ok, pid} =
      Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
        result = run(action, params, context, opts)
        send(parent, {:action_async_result, ref, result})
        result
      end)

    # We monitor the newly created Task so we can handle :DOWN messages in `await`.
    Process.monitor(pid)

    dbug("Async action started", ref: ref, pid: pid)
    %{ref: ref, pid: pid}
  end

  @doc """
  Waits for the result of an asynchronous Action execution.

  ## Parameters

  - `async_ref`: The reference returned by `run_async/4`.
  - `timeout`: Maximum time (in ms) to wait for the result (default: 5000).

  ## Returns

  - `{:ok, result}` if the Action executes successfully.
  - `{:error, reason}` if an error occurs during execution or if the action times out.

  ## Examples

      iex> async_ref = Jido.Exec.run_async(MyAction, %{input: "value"})
      iex> Jido.Exec.await(async_ref, 10_000)
      {:ok, %{result: "processed value"}}

      iex> async_ref = Jido.Exec.run_async(SlowAction, %{input: "value"})
      iex> Jido.Exec.await(async_ref, 100)
      {:error, %Jido.Error{type: :timeout, message: "Async action timed out after 100ms"}}
  """
  @spec await(async_ref(), timeout()) :: {:ok, map()} | {:error, Error.t()}
  def await(%{ref: ref, pid: pid}, timeout \\ 5000) do
    dbug("Awaiting async action result", ref: ref, pid: pid, timeout: timeout)

    receive do
      {:action_async_result, ^ref, result} ->
        dbug("Received async result", result: result)
        result

      {:DOWN, _monitor_ref, :process, ^pid, :normal} ->
        dbug("Process completed normally")
        # Process completed normally, but we might still receive the result
        receive do
          {:action_async_result, ^ref, result} ->
            dbug("Received delayed result", result: result)
            result
        after
          100 ->
            dbug("No result received after normal completion")
            {:error, Error.execution_error("Process completed but result was not received")}
        end

      {:DOWN, _monitor_ref, :process, ^pid, reason} ->
        dbug("Process crashed", reason: reason)
        {:error, Error.execution_error("Server error in async action: #{inspect(reason)}")}
    after
      timeout ->
        dbug("Async action timed out", timeout: timeout)
        Process.exit(pid, :kill)

        receive do
          {:DOWN, _, :process, ^pid, _} -> :ok
        after
          0 -> :ok
        end

        {:error, Error.timeout("Async action timed out after #{timeout}ms")}
    end
  end

  @doc """
  Cancels a running asynchronous Action execution.

  ## Parameters

  - `async_ref`: The reference returned by `run_async/4`, or just the PID of the process to cancel.

  ## Returns

  - `:ok` if the cancellation was successful.
  - `{:error, reason}` if the cancellation failed or the input was invalid.

  ## Examples

      iex> async_ref = Jido.Exec.run_async(LongRunningAction, %{input: "value"})
      iex> Jido.Exec.cancel(async_ref)
      :ok

      iex> Jido.Exec.cancel("invalid")
      {:error, %Jido.Error{type: :invalid_async_ref, message: "Invalid async ref for cancellation"}}
  """
  @spec cancel(async_ref() | pid()) :: :ok | {:error, Error.t()}
  def cancel(%{ref: _ref, pid: pid}), do: cancel(pid)
  def cancel(%{pid: pid}), do: cancel(pid)

  def cancel(pid) when is_pid(pid) do
    dbug("Cancelling action", pid: pid)
    Process.exit(pid, :shutdown)
    :ok
  end

  def cancel(_), do: {:error, Error.invalid_async_ref("Invalid async ref for cancellation")}

  # Private functions are exposed to the test suite
  private do
    @spec normalize_params(params()) :: {:ok, map()} | {:error, Error.t()}
    defp normalize_params(%Error{} = error), do: OK.failure(error)
    defp normalize_params(params) when is_map(params), do: OK.success(params)
    defp normalize_params(params) when is_list(params), do: OK.success(Map.new(params))
    defp normalize_params({:ok, params}) when is_map(params), do: OK.success(params)
    defp normalize_params({:ok, params}) when is_list(params), do: OK.success(Map.new(params))
    defp normalize_params({:error, reason}), do: OK.failure(Error.validation_error(reason))

    defp normalize_params(params),
      do: OK.failure(Error.validation_error("Invalid params type: #{inspect(params)}"))

    @spec normalize_context(context()) :: {:ok, map()} | {:error, Error.t()}
    defp normalize_context(context) when is_map(context), do: OK.success(context)
    defp normalize_context(context) when is_list(context), do: OK.success(Map.new(context))

    defp normalize_context(context),
      do: OK.failure(Error.validation_error("Invalid context type: #{inspect(context)}"))

    @spec validate_action(action()) :: :ok | {:error, Error.t()}
    defp validate_action(action) do
      dbug("Validating action", action: action)

      case Code.ensure_compiled(action) do
        {:module, _} ->
          if function_exported?(action, :run, 2) do
            :ok
          else
            {:error,
             Error.invalid_action(
               "Module #{inspect(action)} is not a valid action: missing run/2 function"
             )}
          end

        {:error, reason} ->
          {:error,
           Error.invalid_action("Failed to compile module #{inspect(action)}: #{inspect(reason)}")}
      end
    end

    @spec validate_params(action(), map()) :: {:ok, map()} | {:error, Error.t()}
    defp validate_params(action, params) do
      dbug("Validating params", action: action, params: params)

      if function_exported?(action, :validate_params, 1) do
        case action.validate_params(params) do
          {:ok, params} ->
            OK.success(params)

          {:error, reason} ->
            OK.failure(reason)

          _ ->
            OK.failure(Error.validation_error("Invalid return from action.validate_params/1"))
        end
      else
        OK.failure(
          Error.invalid_action(
            "Module #{inspect(action)} is not a valid action: missing validate_params/1 function"
          )
        )
      end
    end

    @spec validate_output(action(), map(), run_opts()) :: {:ok, map()} | {:error, Error.t()}
    defp validate_output(action, output, opts) do
      log_level = Keyword.get(opts, :log_level, :info)
      dbug("Validating output", action: action, output: output)

      if function_exported?(action, :validate_output, 1) do
        case action.validate_output(output) do
          {:ok, validated_output} ->
            cond_log(log_level, :debug, "Output validation succeeded for #{inspect(action)}")
            OK.success(validated_output)

          {:error, reason} ->
            cond_log(
              log_level,
              :debug,
              "Output validation failed for #{inspect(action)}: #{inspect(reason)}"
            )

            OK.failure(reason)

          _ ->
            cond_log(log_level, :debug, "Invalid return from action.validate_output/1")
            OK.failure(Error.validation_error("Invalid return from action.validate_output/1"))
        end
      else
        # If action doesn't have validate_output/1, skip output validation
        cond_log(
          log_level,
          :debug,
          "No output validation function found for #{inspect(action)}, skipping"
        )

        OK.success(output)
      end
    end

    @spec do_run_with_retry(action(), params(), context(), run_opts()) ::
            {:ok, map()} | {:error, Error.t()}
    defp do_run_with_retry(action, params, context, opts) do
      max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
      backoff = Keyword.get(opts, :backoff, @initial_backoff)
      dbug("Starting run with retry", action: action, max_retries: max_retries, backoff: backoff)
      do_run_with_retry(action, params, context, opts, 0, max_retries, backoff)
    end

    @spec do_run_with_retry(
            action(),
            params(),
            context(),
            run_opts(),
            non_neg_integer(),
            non_neg_integer(),
            non_neg_integer()
          ) :: {:ok, map()} | {:error, Error.t()}
    defp do_run_with_retry(action, params, context, opts, retry_count, max_retries, backoff) do
      dbug("Attempting run", action: action, retry_count: retry_count)

      case do_run(action, params, context, opts) do
        OK.success(result) ->
          dbug("Run succeeded", result: result)
          OK.success(result)

        {:ok, result, other} ->
          dbug("Run succeeded with additional info", result: result, other: other)
          {:ok, result, other}

        {:error, reason, other} ->
          dbug("Run failed with additional info", error: reason, other: other)

          maybe_retry(
            action,
            params,
            context,
            opts,
            retry_count,
            max_retries,
            backoff,
            {:error, reason, other}
          )

        OK.failure(reason) ->
          dbug("Run failed", error: reason)

          maybe_retry(
            action,
            params,
            context,
            opts,
            retry_count,
            max_retries,
            backoff,
            OK.failure(reason)
          )
      end
    end

    defp maybe_retry(action, params, context, opts, retry_count, max_retries, backoff, error) do
      if retry_count < max_retries do
        backoff = calculate_backoff(retry_count, backoff)

        cond_log(
          Keyword.get(opts, :log_level, :info),
          :info,
          "Retrying #{inspect(action)} (attempt #{retry_count + 1}/#{max_retries}) after #{backoff}ms backoff"
        )

        dbug("Retrying after backoff",
          action: action,
          retry_count: retry_count,
          max_retries: max_retries,
          backoff: backoff
        )

        :timer.sleep(backoff)

        do_run_with_retry(
          action,
          params,
          context,
          opts,
          retry_count + 1,
          max_retries,
          backoff
        )
      else
        dbug("Max retries reached", action: action, max_retries: max_retries)
        error
      end
    end

    @spec calculate_backoff(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
    defp calculate_backoff(retry_count, backoff) do
      (backoff * :math.pow(2, retry_count))
      |> round()
      |> min(30_000)
    end

    @spec do_run(action(), params(), context(), run_opts()) ::
            {:ok, map()} | {:error, Error.t()}
    defp do_run(action, params, context, opts) do
      timeout = Keyword.get(opts, :timeout)
      telemetry = Keyword.get(opts, :telemetry, :full)
      dbug("Starting action execution", action: action, timeout: timeout, telemetry: telemetry)

      result =
        case telemetry do
          :silent ->
            execute_action_with_timeout(action, params, context, timeout)

          _ ->
            start_time = System.monotonic_time(:microsecond)
            start_span(action, params, context, telemetry)

            result = execute_action_with_timeout(action, params, context, timeout, opts)

            end_time = System.monotonic_time(:microsecond)
            duration_us = end_time - start_time
            end_span(action, result, duration_us, telemetry)

            result
        end

      case result do
        {:ok, _result} = success ->
          dbug("Action succeeded", result: success)
          success

        {:ok, _result, _other} = success ->
          dbug("Action succeeded with additional info", result: success)
          success

        {:error, %Error{type: :timeout}} = timeout_err ->
          dbug("Action timed out", error: timeout_err)
          timeout_err

        {:error, error, other} ->
          dbug("Action failed with additional info", error: error, other: other)
          handle_action_error(action, params, context, {error, other}, opts)

        {:error, error} ->
          dbug("Action failed", error: error)
          handle_action_error(action, params, context, error, opts)
      end
    end

    @spec start_span(action(), params(), context(), atom()) :: :ok
    defp start_span(action, params, context, telemetry) do
      metadata = %{
        action: action,
        params: params,
        context: context
      }

      emit_telemetry_event(:start, metadata, telemetry)
    end

    @spec end_span(action(), {:ok, map()} | {:error, Error.t()}, non_neg_integer(), atom()) ::
            :ok
    defp end_span(action, result, duration_us, telemetry) do
      metadata = get_metadata(action, result, duration_us, telemetry)

      status =
        case result do
          {:ok, _} -> :complete
          {:ok, _, _} -> :complete
          _ -> :error
        end

      emit_telemetry_event(status, metadata, telemetry)
    end

    @spec get_metadata(action(), {:ok, map()} | {:error, Error.t()}, non_neg_integer(), atom()) ::
            map()
    defp get_metadata(action, result, duration_us, :full) do
      %{
        action: action,
        result: result,
        duration_us: duration_us,
        memory_usage: :erlang.memory(),
        process_info: get_process_info(),
        node: node()
      }
    end

    @spec get_metadata(action(), {:ok, map()} | {:error, Error.t()}, non_neg_integer(), atom()) ::
            map()
    defp get_metadata(action, result, duration_us, :minimal) do
      %{
        action: action,
        result: result,
        duration_us: duration_us
      }
    end

    @spec get_process_info() :: map()
    defp get_process_info do
      for key <- [:reductions, :message_queue_len, :total_heap_size, :garbage_collection],
          into: %{} do
        {key, self() |> Process.info(key) |> elem(1)}
      end
    end

    @spec emit_telemetry_event(atom(), map(), atom()) :: :ok
    defp emit_telemetry_event(event, metadata, telemetry) when telemetry in [:full, :minimal] do
      event_name = [:jido, :action, event]
      measurements = %{system_time: System.system_time()}

      :telemetry.execute(event_name, measurements, metadata)
    end

    defp emit_telemetry_event(_, _, _), do: :ok

    # In handle_action_error:
    @spec handle_action_error(
            action(),
            params(),
            context(),
            Error.t() | {Error.t(), any()},
            run_opts()
          ) ::
            {:error, Error.t() | map()} | {:error, Error.t(), any()}
    defp handle_action_error(action, params, context, error_or_tuple, opts) do
      Logger.debug("Handle Action Error in handle_action_error: #{inspect(opts)}")
      dbug("Handling action error", action: action, error: error_or_tuple)

      # Extract error and directive if present
      {error, directive} =
        case error_or_tuple do
          {error, directive} -> {error, directive}
          error -> {error, nil}
        end

      if compensation_enabled?(action) do
        metadata = action.__action_metadata__()
        compensation_opts = metadata[:compensation] || []

        timeout =
          Keyword.get(opts, :timeout) ||
            case compensation_opts do
              opts when is_list(opts) -> Keyword.get(opts, :timeout, 5_000)
              %{timeout: timeout} -> timeout
              _ -> 5_000
            end

        dbug("Starting compensation", action: action, timeout: timeout)

        task =
          Task.async(fn ->
            action.on_error(params, error, context, [])
          end)

        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, result} ->
            dbug("Compensation completed", result: result)
            handle_compensation_result(result, error, directive)

          nil ->
            dbug("Compensation timed out", timeout: timeout)

            error_result =
              Error.compensation_error(
                error,
                %{
                  compensated: false,
                  compensation_error: "Compensation timed out after #{timeout}ms"
                }
              )

            if directive, do: {:error, error_result, directive}, else: OK.failure(error_result)
        end
      else
        dbug("Compensation not enabled", action: action)
        if directive, do: {:error, error, directive}, else: OK.failure(error)
      end
    end

    @spec handle_compensation_result(any(), Error.t(), any()) ::
            {:error, Error.t()} | {:error, Error.t(), any()}
    defp handle_compensation_result(result, original_error, directive) do
      error_result =
        case result do
          {:ok, comp_result} ->
            # Extract fields that should be at the top level of the details
            {top_level_fields, remaining_fields} =
              Map.split(comp_result, [:test_value, :compensation_context])

            # Create the details map with the compensation result
            details =
              Map.merge(
                %{
                  compensated: true,
                  compensation_result: remaining_fields
                },
                top_level_fields
              )

            Error.compensation_error(original_error, details)

          {:error, comp_error} ->
            Error.compensation_error(
              original_error,
              %{
                compensated: false,
                compensation_error: comp_error
              }
            )

          _ ->
            Error.compensation_error(
              original_error,
              %{
                compensated: false,
                compensation_error: "Invalid compensation result"
              }
            )
        end

      if directive, do: {:error, error_result, directive}, else: OK.failure(error_result)
    end

    @spec compensation_enabled?(action()) :: boolean()
    defp compensation_enabled?(action) do
      metadata = action.__action_metadata__()
      compensation_opts = metadata[:compensation] || []

      enabled =
        case compensation_opts do
          opts when is_list(opts) -> Keyword.get(opts, :enabled, false)
          %{enabled: enabled} -> enabled
          _ -> false
        end

      enabled && function_exported?(action, :on_error, 4)
    end

    @spec execute_action_with_timeout(action(), params(), context(), non_neg_integer()) ::
            {:ok, map()} | {:error, Error.t()}
    defp execute_action_with_timeout(action, params, context, timeout, opts \\ [])

    defp execute_action_with_timeout(action, params, context, 0, opts) do
      execute_action(action, params, context, opts)
    end

    defp execute_action_with_timeout(action, params, context, timeout, opts)
         when is_integer(timeout) and timeout > 0 do
      parent = self()
      ref = make_ref()

      dbug("Starting action with timeout", action: action, timeout: timeout)

      # Create a temporary task group for this execution
      {:ok, task_group} =
        Task.Supervisor.start_child(
          Jido.TaskSupervisor,
          fn ->
            Process.flag(:trap_exit, true)

            receive do
              {:shutdown} -> :ok
            end
          end
        )

      # Add task_group to context so Actions can use it
      enhanced_context = Map.put(context, :__task_group__, task_group)

      # Get the current process's group leader
      current_gl = Process.group_leader()

      {pid, monitor_ref} =
        spawn_monitor(fn ->
          # Use the parent's group leader to ensure IO is properly captured
          Process.group_leader(self(), current_gl)

          result =
            try do
              dbug("Executing action in task", action: action, pid: self())
              result = execute_action(action, params, enhanced_context, opts)
              dbug("Action execution completed", action: action, result: result)
              result
            catch
              kind, reason ->
                stacktrace = __STACKTRACE__
                dbug("Action execution caught error", action: action, kind: kind, reason: reason)

                {:error,
                 Error.execution_error(
                   "Caught #{kind}: #{inspect(reason)}",
                   %{kind: kind, reason: reason, action: action},
                   stacktrace
                 )}
            end

          send(parent, {:done, ref, result})
        end)

      result =
        receive do
          {:done, ^ref, result} ->
            dbug("Received action result", action: action, result: result)
            cleanup_task_group(task_group)
            Process.demonitor(monitor_ref, [:flush])
            result

          {:DOWN, ^monitor_ref, :process, ^pid, :killed} ->
            dbug("Task was killed", action: action)
            cleanup_task_group(task_group)
            {:error, Error.execution_error("Task was killed")}

          {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
            dbug("Task exited unexpectedly", action: action, reason: reason)
            cleanup_task_group(task_group)
            {:error, Error.execution_error("Task exited: #{inspect(reason)}")}
        after
          timeout ->
            dbug("Action timed out", action: action, timeout: timeout)
            cleanup_task_group(task_group)
            Process.exit(pid, :kill)

            receive do
              {:DOWN, ^monitor_ref, :process, ^pid, _} -> :ok
            after
              0 -> :ok
            end

            {:error,
             Error.timeout(
               "Action #{inspect(action)} timed out after #{timeout}ms. This could be due to:
1. The action is taking too long to complete (current timeout: #{timeout}ms)
2. The action is stuck in an infinite loop
3. The action's return value doesn't match the expected format ({:ok, map()} | {:ok, map(), directive} | {:error, reason})
4. An unexpected error occurred without proper error handling
5. The action may be using unsafe IO operations (IO.inspect, etc).

Debug info:
- Action module: #{inspect(action)}
- Params: #{inspect(params)}
- Context: #{inspect(Map.drop(context, [:__task_group__]))}"
             )}
        end

      result
    end

    defp execute_action_with_timeout(action, params, context, _timeout, opts) do
      execute_action_with_timeout(action, params, context, @default_timeout, opts)
    end

    defp cleanup_task_group(task_group) do
      send(task_group, {:shutdown})

      Process.exit(task_group, :kill)

      Task.Supervisor.children(Jido.TaskSupervisor)
      |> Enum.filter(fn pid ->
        case Process.info(pid, :group_leader) do
          {:group_leader, ^task_group} -> true
          _ -> false
        end
      end)
      |> Enum.each(&Process.exit(&1, :kill))
    end

    @spec execute_action(action(), params(), context(), run_opts()) ::
            {:ok, map()} | {:error, Error.t()}
    defp execute_action(action, params, context, opts) do
      log_level = Keyword.get(opts, :log_level, :info)
      dbug("Executing action", action: action, params: params, context: context)

      cond_log(
        log_level,
        :debug,
        "Starting execution of #{inspect(action)}, params: #{inspect(params)}, context: #{inspect(context)}"
      )

      case action.run(params, context) do
        {:ok, result, other} ->
          dbug("Action succeeded with additional info", result: result, other: other)

          case validate_output(action, result, opts) do
            {:ok, validated_result} ->
              cond_log(
                log_level,
                :debug,
                "Finished execution of #{inspect(action)}, result: #{inspect(validated_result)}, directive: #{inspect(other)}"
              )

              {:ok, validated_result, other}

            {:error, validation_error} ->
              dbug("Action output validation failed", error: validation_error)

              cond_log(
                log_level,
                :error,
                "Action #{inspect(action)} output validation failed: #{inspect(validation_error)}"
              )

              {:error, validation_error, other}
          end

        OK.success(result) ->
          dbug("Action succeeded", result: result)

          case validate_output(action, result, opts) do
            {:ok, validated_result} ->
              cond_log(
                log_level,
                :debug,
                "Finished execution of #{inspect(action)}, result: #{inspect(validated_result)}"
              )

              OK.success(validated_result)

            {:error, validation_error} ->
              dbug("Action output validation failed", error: validation_error)

              cond_log(
                log_level,
                :error,
                "Action #{inspect(action)} output validation failed: #{inspect(validation_error)}"
              )

              OK.failure(validation_error)
          end

        {:error, reason, other} ->
          dbug("Action failed with additional info", error: reason, other: other)
          cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(reason)}")
          {:error, reason, other}

        OK.failure(%Error{} = error) ->
          dbug("Action failed with error struct", error: error)
          cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(error)}")
          OK.failure(error)

        OK.failure(reason) ->
          dbug("Action failed with reason", reason: reason)
          cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(reason)}")
          OK.failure(Error.execution_error(reason))

        result ->
          dbug("Action returned unexpected result", result: result)

          case validate_output(action, result, opts) do
            {:ok, validated_result} ->
              cond_log(
                log_level,
                :debug,
                "Finished execution of #{inspect(action)}, result: #{inspect(validated_result)}"
              )

              OK.success(validated_result)

            {:error, validation_error} ->
              dbug("Action output validation failed", error: validation_error)

              cond_log(
                log_level,
                :error,
                "Action #{inspect(action)} output validation failed: #{inspect(validation_error)}"
              )

              OK.failure(validation_error)
          end
      end
    rescue
      e in RuntimeError ->
        dbug("Runtime error in action", error: e)
        stacktrace = __STACKTRACE__
        log_level = Keyword.get(opts, :log_level, :info)
        cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(e)}")

        OK.failure(
          Error.execution_error(
            "Server error in #{inspect(action)}: #{Exception.message(e)}",
            %{original_exception: e, action: action},
            stacktrace
          )
        )

      e in ArgumentError ->
        dbug("Argument error in action", error: e)
        stacktrace = __STACKTRACE__
        log_level = Keyword.get(opts, :log_level, :info)
        cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(e)}")

        OK.failure(
          Error.execution_error(
            "Argument error in #{inspect(action)}: #{Exception.message(e)}",
            %{original_exception: e, action: action},
            stacktrace
          )
        )

      e ->
        stacktrace = __STACKTRACE__
        log_level = Keyword.get(opts, :log_level, :info)
        cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(e)}")

        OK.failure(
          Error.execution_error(
            "An unexpected error occurred during execution of #{inspect(action)}: #{inspect(e)}",
            %{original_exception: e, action: action},
            stacktrace
          )
        )
    end
  end
end
