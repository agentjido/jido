defmodule JidoTest.TestActions do
  @moduledoc false
  import OK, only: [success: 1, failure: 1]

  alias Jido.Error
  alias Jido.Action

  defmodule BasicAction do
    @moduledoc false
    use Action,
      name: "basic_action",
      description: "A basic action for testing",
      schema: [
        value: [type: :integer, required: true]
      ]

    def run(%{value: value}, _context) do
      {:ok, %{value: value}}
    end
  end

  defmodule RawResultAction do
    @moduledoc false
    use Action,
      name: "raw_result_action",
      schema: [
        value: [type: :integer, required: true]
      ]

    def run(%{value: value}, _context) do
      %{value: value}
    end
  end

  defmodule NoSchema do
    @moduledoc false
    use Action,
      name: "add_two",
      description: "Adds 2 to the input value"

    def run(%{value: value}, _context), do: {:ok, %{result: value + 2}}

    # Allow no params
    def run(_params, _context), do: {:ok, %{result: "No params"}}
  end

  defmodule NoParamsAction do
    @moduledoc false
    use Action,
      name: "no_params_action",
      description: "A action with no parameters"

    def run(_params, _context), do: {:ok, %{result: "No params"}}
  end

  defmodule FullAction do
    @moduledoc false
    use Action,
      name: "full_action",
      description: "A full action for testing",
      category: "test",
      tags: ["test", "full"],
      vsn: "1.0.0",
      schema: [
        a: [type: :integer, required: true],
        b: [type: :integer, required: true]
      ]

    @impl true
    def on_before_validate_params(params) do
      with {:ok, a} <- validate_positive_integer(params[:a]),
           {:ok, b} <- validate_multiple_of_two(params[:b]) do
        {:ok, %{params | a: a, b: b}}
      end
    end

    defp validate_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

    defp validate_positive_integer(_),
      do: {:error, Error.validation_error("Parameter 'a' must be a positive integer")}

    defp validate_multiple_of_two(value) when is_integer(value) and rem(value, 2) == 0,
      do: {:ok, value}

    defp validate_multiple_of_two(_),
      do: {:error, Error.validation_error("Parameter 'b' must be a multiple of 2")}

    @impl true
    def on_after_validate_params(params) do
      params =
        params
        |> Map.put(:timestamp, System.system_time(:millisecond))
        |> Map.put(:id, :rand.uniform(1000))

      {:ok, params}
    end

    @impl true
    def run(params, _context) do
      result = params.a + params.b
      {:ok, Map.put(params, :result, result)}
    end

    @impl true
    def on_after_run(result) do
      {:ok, Map.put(result, :execution_time, System.system_time(:millisecond) - result.timestamp)}
    end

    @impl true
    def on_error(failed_params, _error, _context, _opts), do: {:ok, failed_params}
  end

  defmodule CompensateAction do
    @moduledoc false
    use Action,
      name: "compensate_action",
      description: "Action that tests compensation behavior",
      compensation: [enabled: true, max_retries: 3, timeout: 250],
      schema: [
        should_fail: [type: :boolean, required: true],
        compensation_should_fail: [type: :boolean, default: false],
        delay: [type: :non_neg_integer, default: 0],
        test_value: [type: :string, default: ""]
      ]

    def run(%{should_fail: true}, _context) do
      {:error, Error.execution_error("Intentional failure")}
    end

    def run(_params, _context) do
      {:ok, %{result: "CompensateAction completed"}}
    end

    def on_error(params, error, context, _opts) do
      if params.compensation_should_fail do
        {:error, Error.execution_error("Compensation failed")}
      else
        if params.delay > 0, do: Process.sleep(params.delay)

        {_top_level_fields, remaining_fields} = Map.split(params, [:test_value])

        {:ok,
         Map.merge(remaining_fields, %{
           compensated: true,
           original_error: error,
           compensation_context: context,
           test_value: params[:test_value]
         })}
      end
    end
  end

  defmodule ErrorAction do
    @moduledoc false
    use Action, name: "error_action"

    def run(%{error_type: :validation}, _context) do
      {:error, "Validation error"}
    end

    def run(%{error_type: :argument}, _context) do
      raise ArgumentError, message: "Argument error"
    end

    def run(%{error_type: :runtime}, _context) do
      raise RuntimeError, message: "Runtime error"
    end

    def run(%{error_type: :custom}, _context) do
      raise "Custom error"
    end

    def run(%{type: :throw}, _context) do
      throw("Action threw an error")
    end

    def run(_params, _context), do: {:error, "Workflow failed"}
  end

  defmodule NormalExitAction do
    @moduledoc false
    use Action,
      name: "normal_exit_action",
      description: "Exits normally"

    def run(_params, _context) do
      Process.exit(self(), :normal)
      {:ok, %{result: "This should never be returned"}}
    end
  end

  defmodule KilledAction do
    @moduledoc false
    use Action,
      name: "killed_action",
      description: "Kills the process"

    def run(_params, _context) do
      # Simulate some work before getting killed
      Process.sleep(50)
      Process.exit(self(), :kill)

      # This line will never be reached
      {:ok, %{result: "This should never be returned"}}
    end
  end

  defmodule SlowKilledAction do
    @moduledoc false
    use Jido.Action,
      name: "slow_killed_action",
      schema: []

    @impl true
    def run(_params, _context) do
      receive do
        :never -> :ok
      end
    end
  end

  defmodule SpawnerAction do
    @moduledoc false
    use Action,
      name: "spawner_action",
      description: "Spawns a new process"

    def run(%{count: count}, _context) do
      for _ <- 1..count do
        spawn(fn -> Process.sleep(10_000) end)
      end

      {:ok, %{result: "Multi-process workflow completed"}}
    end
  end

  defmodule Add do
    @moduledoc false
    use Action,
      name: "add_one",
      description: "Adds 1 to the input value",
      schema: [
        value: [type: :integer, required: true],
        amount: [type: :integer, default: 1]
      ]

    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{value: value + amount}}
    end
  end

  defmodule Multiply do
    @moduledoc false
    use Action,
      name: "multiply",
      description: "Multiplies the input value by 2",
      schema: [
        value: [type: :integer, required: true],
        amount: [type: :integer, default: 2]
      ]

    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{value: value * amount}}
    end
  end

  defmodule ContextAwareMultiply do
    @moduledoc false
    use Action, name: "context_aware_multiply"

    def run(%{value: value}, %{multiplier: multiplier}), do: {:ok, %{value: value * multiplier}}
  end

  defmodule Subtract do
    @moduledoc false
    use Action,
      name: "subtract",
      description: "Subtracts second value from first value",
      schema: [
        value: [type: :integer, required: true],
        amount: [type: :integer, default: 1]
      ]

    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{value: value - amount}}
    end
  end

  defmodule Divide do
    @moduledoc false
    use Action,
      name: "divide",
      description: "Divides first value by second value",
      schema: [
        value: [type: :float, required: true],
        amount: [type: :float, default: 2]
      ]

    def run(%{value: value, amount: amount}, _context) when amount != 0 do
      {:ok, %{value: value / amount}}
    end

    def run(_, _context) do
      raise "Cannot divide by zero"
    end
  end

  defmodule Square do
    @moduledoc false
    use Action,
      name: "square",
      description: "Squares the input value",
      schema: [
        value: [type: :integer, required: true]
      ]

    def run(%{value: value}, _context) do
      {:ok, %{value: value * value}}
    end
  end

  defmodule WriteFile do
    @moduledoc false
    use Action,
      name: "write_file",
      description: "Writes a file to the filesystem",
      schema: [
        file_name: [type: :string, required: true],
        content: [type: :string, required: true]
      ]

    def run(%{file_name: file_name, content: _content} = params, _context) do
      # Simulate file writing
      {:ok, Map.put(params, :written_file, file_name)}
    end
  end

  defmodule SchemaAction do
    @moduledoc false
    use Action,
      name: "schema_action",
      description: "A action with a complex schema and custom validation",
      schema: [
        string: [type: :string],
        integer: [type: :integer],
        atom: [type: :atom],
        boolean: [type: :boolean],
        list: [type: {:list, :string}],
        keyword_list: [type: :keyword_list],
        map: [type: :map],
        custom: [type: {:custom, __MODULE__, :validate_custom, []}]
      ]

    @spec validate_custom(any()) :: {:error, <<_::128>>} | {:ok, atom()}
    def validate_custom(value) when is_binary(value), do: {:ok, String.to_atom(value)}
    def validate_custom(_), do: {:error, "must be a string"}

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule DelayAction do
    @moduledoc false
    use Action,
      name: "delay_action",
      description: "Simulates a delay in workflow",
      schema: [
        delay: [type: :integer, default: 1000, doc: "Delay in milliseconds"]
      ]

    def run(%{delay: delay}, _context) do
      Process.sleep(delay)
      {:ok, %{result: "Async workflow completed"}}
    end
  end

  defmodule ContextAction do
    @moduledoc false
    use Action,
      name: "context_aware_action",
      description: "Uses context in its workflow",
      schema: [
        input: [type: :string, required: true]
      ]

    def run(%{input: input}, context) do
      {:ok, %{result: "#{input} processed with context: #{inspect(context)}"}}
    end
  end

  defmodule ResultAction do
    @moduledoc false
    use Action,
      name: "result_action",
      description: "Returns configurable result types",
      schema: [
        result_type: [type: {:in, [:success, :failure, :raw]}, required: true]
      ]

    def run(%{result_type: :success}, _context) do
      success(%{result: "success"})
    end

    def run(%{result_type: :failure}, _context) do
      failure(Error.internal_server_error("Simulated failure"))
    end

    def run(%{result_type: :raw}, _context) do
      %{result: "raw_result"}
    end
  end

  defmodule RetryAction do
    @moduledoc """
    Simulates an workflow with configurable retry behavior.
    """
    use Action,
      name: "retry_action",
      description: "Simulates an workflow with configurable retry behavior",
      schema: [
        max_attempts: [type: :integer, default: 3],
        failure_type: [type: {:in, [:error, :exception]}, default: :error]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, any()}
    def run(%{max_attempts: max_attempts, failure_type: failure_type}, context) do
      attempts_table = context.attempts_table

      # Get the current attempt count
      attempts =
        :ets.update_counter(attempts_table, :attempts, {2, 1, max_attempts, max_attempts})

      if attempts < max_attempts do
        # Simulate failure based on the failure_type
        case failure_type do
          :error -> {:error, Error.internal_server_error("Retry needed")}
          :exception -> raise "Retry exception"
        end
      else
        # Success on the last attempt
        {:ok, %{result: "success after #{attempts} attempts"}}
      end
    end
  end

  defmodule LongRunningAction do
    @moduledoc false
    use Action, name: "long_running_action"

    def run(_params, _context) do
      Enum.each(1..10, fn _ ->
        Process.sleep(10)
        if :persistent_term.get({__MODULE__, :cancel}, false), do: throw(:cancelled)
      end)

      success("Workflow completed")
    catch
      :throw, :cancelled -> failure("Workflow cancelled")
    after
      :persistent_term.erase({__MODULE__, :cancel})
    end
  end

  defmodule RateLimitedAction do
    @moduledoc false
    use Action,
      name: "rate_limited_action",
      description: "Demonstrates rate limiting functionality",
      schema: [
        workflow: [type: :string, required: true]
      ]

    @max_requests 5
    # 1 minute in milliseconds
    @time_window 60_000

    def run(%{workflow: workflow}, _context) do
      case check_rate_limit() do
        :ok ->
          {:ok, %{result: "Workflow '#{workflow}' executed successfully"}}

        :error ->
          {:error, "Rate limit exceeded. Please try again later."}
      end
    end

    defp check_rate_limit do
      current_time = System.system_time(:millisecond)
      requests = :persistent_term.get({__MODULE__, :requests}, [])

      requests =
        Enum.filter(requests, fn timestamp -> current_time - timestamp < @time_window end)

      if length(requests) < @max_requests do
        :persistent_term.put({__MODULE__, :requests}, [current_time | requests])
        :ok
      else
        :error
      end
    end
  end

  defmodule StreamingAction do
    @moduledoc false
    use Action,
      name: "streaming_action",
      description: "Showcases streaming or chunked data processing",
      schema: [
        chunk_size: [type: :integer, default: 10],
        total_items: [type: :integer, default: 100]
      ]

    def run(%{chunk_size: chunk_size, total_items: total_items}, _context) do
      stream =
        1
        |> Stream.iterate(&(&1 + 1))
        |> Stream.take(total_items)
        |> Stream.chunk_every(chunk_size)
        |> Stream.map(fn chunk ->
          # Simulate processing time
          Process.sleep(10)
          Enum.sum(chunk)
        end)

      {:ok, %{stream: stream}}
    end
  end

  defmodule ConcurrentAction do
    @moduledoc false
    use Action,
      name: "concurrent_action",
      description: "Showcases concurrent processing of multiple inputs",
      schema: [
        inputs: [type: {:list, :integer}, required: true]
      ]

    def run(%{inputs: inputs}, _context) do
      results =
        inputs
        |> Task.async_stream(
          fn input ->
            # Simulate varying processing times
            Process.sleep(:rand.uniform(100))
            input * 2
          end,
          timeout: 5000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      {:ok, %{results: results}}
    end
  end
end
