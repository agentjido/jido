defmodule Jido.Workflow do
  @moduledoc """
  Workflows are the Action runtime. They provide a robust framework for executing and managing workflows (multiple Actions) in a distributed system.

  This module offers functionality to:
  - Run workflows synchronously or asynchronously
  - Manage timeouts and retries
  - Cancel running workflows
  - Normalize and validate input parameters and context
  - Emit telemetry events for monitoring and debugging

  Workflows are defined as modules (Actions) that implement specific callbacks, allowing for
  a standardized way of defining and executing complex workflows across a distributed system.

  ## Features

  - Synchronous and asynchronous workflow execution
  - Automatic retries with exponential backoff
  - Timeout handling for long-running workflows
  - Parameter and context normalization
  - Comprehensive error handling and reporting
  - Telemetry integration for monitoring and tracing
  - Cancellation of running workflows

  ## Usage

  Workflows are executed using the `run/4` or `run_async/4` functions:

      Jido.Workflow.run(MyAction, %{param1: "value"}, %{context_key: "context_value"})

  See `Jido.Action` for how to define a Action.

  For asynchronous execution:

      async_ref = Jido.Workflow.run_async(MyAction, params, context)
      # ... do other work ...
      result = Jido.Workflow.await(async_ref)

  """
  use Private

  alias Jido.Error

  require Logger
  require OK

  @default_timeout 5000
  @default_max_retries 1
  @initial_backoff 1000

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

  ## Returns

  - `{:ok, result}` if the Action executes successfully.
  - `{:error, reason}` if an error occurs during execution.

  ## Examples

      iex> Jido.Workflow.run(MyAction, %{input: "value"}, %{user_id: 123})
      {:ok, %{result: "processed value"}}

      iex> Jido.Workflow.run(MyAction, %{invalid: "input"}, %{}, timeout: 1000)
      {:error, %Jido.Error{type: :validation_error, message: "Invalid input"}}

  """
  @spec run(action(), params(), context(), run_opts()) :: {:ok, map()} | {:error, Error.t()}
  def run(action, params \\ %{}, context \\ %{}, opts \\ [])

  def run(action, params, context, opts) when is_atom(action) and is_list(opts) do
    with {:ok, normalized_params} <- normalize_params(params),
         {:ok, normalized_context} <- normalize_context(context),
         :ok <- validate_action(action),
         OK.success(validated_params) <- validate_params(action, normalized_params) do
      do_run_with_retry(action, validated_params, normalized_context, opts)
    else
      {:error, reason} -> OK.failure(reason)
    end
  rescue
    e in [FunctionClauseError, BadArityError, BadFunctionError] ->
      OK.failure(Error.invalid_action("Invalid action module: #{Exception.message(e)}"))

    e ->
      OK.failure(
        Error.internal_server_error("An unexpected error occurred: #{Exception.message(e)}")
      )
  catch
    kind, reason ->
      OK.failure(Error.internal_server_error("Caught #{kind}: #{inspect(reason)}"))
  end

  def run(action, _params, _context, _opts) do
    OK.failure(Error.invalid_action("Expected action to be a module, got: #{inspect(action)}"))
  end

  @doc """
  Executes a Action asynchronously with the given parameters and context.

  This function immediately returns a reference that can be used to await the result
  or cancel the workflow.

  ## Parameters

  - `action`: The module implementing the Action behavior.
  - `params`: A map of input parameters for the Action.
  - `context`: A map providing additional context for the Action execution.
  - `opts`: Options controlling the execution (same as `run/4`).

  ## Returns

  An `async_ref` map containing:
  - `:ref` - A unique reference for this async workflow.
  - `:pid` - The PID of the process executing the Action.

  ## Examples

      iex> async_ref = Jido.Workflow.run_async(MyAction, %{input: "value"}, %{user_id: 123})
      %{ref: #Reference<0.1234.5678>, pid: #PID<0.234.0>}

      iex> result = Jido.Workflow.await(async_ref)
      {:ok, %{result: "processed value"}}

  """
  @spec run_async(action(), params(), context(), run_opts()) :: async_ref()
  def run_async(action, params \\ %{}, context \\ %{}, opts \\ []) do
    caller = self()
    ref = make_ref()

    {pid, _} =
      spawn_monitor(fn ->
        result = run(action, params, context, opts)
        send(caller, {:action_async_result, ref, result})
      end)

    %{ref: ref, pid: pid}
  end

  @doc """
  Waits for the result of an asynchronous Action execution.

  ## Parameters

  - `async_ref`: The reference returned by `run_async/4`.
  - `timeout`: Maximum time (in ms) to wait for the result (default: 5000).

  ## Returns

  - `{:ok, result}` if the Action executes successfully.
  - `{:error, reason}` if an error occurs during execution or if the workflow times out.

  ## Examples

      iex> async_ref = Jido.Workflow.run_async(MyAction, %{input: "value"})
      iex> Jido.Workflow.await(async_ref, 10_000)
      {:ok, %{result: "processed value"}}

      iex> async_ref = Jido.Workflow.run_async(SlowAction, %{input: "value"})
      iex> Jido.Workflow.await(async_ref, 100)
      {:error, %Jido.Error{type: :timeout, message: "Async workflow timed out after 100ms"}}

  """
  @spec await(async_ref(), timeout()) :: {:ok, map()} | {:error, Error.t()}
  def await(%{ref: ref, pid: pid}, timeout \\ 5000) do
    receive do
      {:action_async_result, ^ref, result} ->
        result

      {:DOWN, _, :process, ^pid, reason} ->
        {:error, Error.execution_error("Async workflow failed: #{inspect(reason)}")}
    after
      timeout ->
        Process.exit(pid, :kill)
        {:error, Error.timeout("Async workflow timed out after #{timeout}ms")}
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

      iex> async_ref = Jido.Workflow.run_async(LongRunningAction, %{input: "value"})
      iex> Jido.Workflow.cancel(async_ref)
      :ok

      iex> Jido.Workflow.cancel("invalid")
      {:error, %Jido.Error{type: :invalid_async_ref, message: "Invalid async ref for cancellation"}}

  """
  @spec cancel(async_ref() | pid()) :: :ok | {:error, Error.t()}
  def cancel(%{ref: _ref, pid: pid}), do: cancel(pid)
  def cancel(%{pid: pid}), do: cancel(pid)

  def cancel(pid) when is_pid(pid) do
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

    @spec do_run_with_retry(action(), params(), context(), run_opts()) ::
            {:ok, map()} | {:error, Error.t()}
    defp do_run_with_retry(action, params, context, opts) do
      max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
      backoff = Keyword.get(opts, :backoff, @initial_backoff)
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
      case do_run(action, params, context, opts) do
        OK.success(result) ->
          OK.success(result)

        OK.failure(reason) ->
          if retry_count < max_retries do
            backoff = calculate_backoff(retry_count, backoff)
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
            OK.failure(reason)
          end
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

      result =
        case telemetry do
          :silent ->
            execute_action_with_timeout(action, params, context, timeout)

          _ ->
            start_time = System.monotonic_time(:microsecond)
            start_span(action, params, context, telemetry)

            result = execute_action_with_timeout(action, params, context, timeout)

            end_time = System.monotonic_time(:microsecond)
            duration_us = end_time - start_time
            end_span(action, result, duration_us, telemetry)

            result
        end

      case result do
        {:ok, _} = success -> success
        {:error, %Error{type: :timeout}} = timeout -> timeout
        {:error, error} -> handle_action_error(action, params, context, error)
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
      status = if match?({:ok, _}, result), do: :complete, else: :error
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
      event_name = [:jido, :workflow, event]
      measurements = %{system_time: System.system_time()}

      Logger.debug("Action #{metadata.action} #{event}", metadata)
      :telemetry.execute(event_name, measurements, metadata)
    end

    defp emit_telemetry_event(_, _, _), do: :ok

    # In handle_action_error:
    @spec handle_action_error(action(), params(), context(), Error.t()) ::
            {:error, Error.t() | map()}
    defp handle_action_error(action, params, context, error) do
      if compensation_enabled?(action) do
        compensation_opts = action.__action_metadata__()[:compensation] || []
        timeout = Keyword.get(compensation_opts, :timeout, 5_000)

        task =
          Task.async(fn ->
            action.on_error(params, error, context, [])
          end)

        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, result} ->
            handle_compensation_result(result, error)

          nil ->
            Error.compensation_error(
              error.message,
              %{
                compensated: false,
                compensation_error: "Compensation timed out after #{timeout}ms",
                original_error: error
              }
            )
            |> OK.failure()
        end
      else
        OK.failure(error)
      end
    end

    @spec handle_compensation_result(map(), Error.t()) :: {:error, Error.t()}
    defp handle_compensation_result(result, original_error) do
      case result do
        OK.success(comp_result) ->
          {top_level_fields, remaining_fields} =
            Map.split(comp_result, [:test_value, :compensation_context])

          Error.compensation_error(
            original_error.message,
            Map.merge(
              %{
                compensated: true,
                original_error: original_error,
                compensation_result: remaining_fields
              },
              top_level_fields
            )
          )
          |> OK.failure()

        OK.failure(comp_error) ->
          Error.compensation_error(
            original_error.message,
            %{
              compensated: false,
              compensation_error: comp_error,
              original_error: original_error
            }
          )
          |> OK.failure()
      end
    end

    @spec compensation_enabled?(action()) :: boolean()
    defp compensation_enabled?(action) do
      compensation_opts = action.__action_metadata__()[:compensation] || []

      Keyword.get(compensation_opts, :enabled, false) &&
        function_exported?(action, :on_error, 4)
    end

    @spec execute_action_with_timeout(action(), params(), context(), non_neg_integer()) ::
            {:ok, map()} | {:error, Error.t()}
    defp execute_action_with_timeout(action, params, context, timeout)

    defp execute_action_with_timeout(action, params, context, 0) do
      execute_action(action, params, context)
    end

    defp execute_action_with_timeout(action, params, context, timeout)
         when is_integer(timeout) and timeout > 0 do
      parent = self()
      ref = make_ref()

      {pid, monitor_ref} =
        spawn_monitor(fn ->
          result =
            try do
              execute_action(action, params, context)
            catch
              kind, reason ->
                {:error, Error.execution_error("Caught #{kind}: #{inspect(reason)}")}
            end

          send(parent, {:done, ref, result})
        end)

      receive do
        {:done, ^ref, result} ->
          Process.demonitor(monitor_ref, [:flush])
          result

        {:DOWN, ^monitor_ref, :process, ^pid, :killed} ->
          {:error, Error.execution_error("Task was killed")}

        {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
          {:error, Error.execution_error("Task exited: #{inspect(reason)}")}
      after
        timeout ->
          Process.exit(pid, :kill)

          receive do
            {:DOWN, ^monitor_ref, :process, ^pid, _} -> :ok
          after
            0 -> :ok
          end

          {:error, Error.timeout("Workflow timed out after #{timeout}ms")}
      end
    end

    defp execute_action_with_timeout(action, params, context, _timeout) do
      execute_action_with_timeout(action, params, context, @default_timeout)
    end

    @spec execute_action(action(), params(), context()) :: {:ok, map()} | {:error, Error.t()}
    defp execute_action(action, params, context) do
      case action.run(params, context) do
        OK.success(result) ->
          OK.success(result)

        OK.failure(reason) ->
          OK.failure(Error.execution_error(reason))

        result ->
          OK.success(result)
      end
    rescue
      e in RuntimeError ->
        OK.failure(
          Error.execution_error("Runtime error in #{inspect(action)}: #{Exception.message(e)}")
        )

      e in ArgumentError ->
        OK.failure(
          Error.execution_error("Argument error in #{inspect(action)}: #{Exception.message(e)}")
        )

      e ->
        OK.failure(
          Error.execution_error(
            "An unexpected error occurred during execution of #{inspect(action)}: #{inspect(e)}"
          )
        )
    end
  end
end
