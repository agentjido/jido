defmodule JidoTest.TestActions do
  @moduledoc false
  import OK, only: [success: 1, failure: 1]

  alias Jido.Error
  alias Jido.Action
  alias Jido.Instruction

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

    @dialyzer {:nowarn_function, run: 2}
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

  defmodule OutputSchemaAction do
    @moduledoc false
    use Action,
      name: "output_schema_action",
      description: "Action that validates output with schema",
      schema: [
        input: [type: :string, required: true]
      ],
      output_schema: [
        result: [type: :string, required: true],
        length: [type: :integer, required: true]
      ]

    def run(%{input: input}, _context) do
      {:ok, %{result: String.upcase(input), length: String.length(input), extra: "not validated"}}
    end
  end

  defmodule InvalidOutputAction do
    @moduledoc false
    use Action,
      name: "invalid_output_action",
      description: "Action that returns invalid output",
      output_schema: [
        required_field: [type: :string, required: true]
      ]

    def run(_params, _context) do
      {:ok, %{wrong_field: "this will fail validation"}}
    end
  end

  defmodule NoOutputSchemaAction do
    @moduledoc false
    use Action,
      name: "no_output_schema_action",
      description: "Action without output schema"

    def run(_params, _context) do
      {:ok, %{anything: "goes", here: 123}}
    end
  end

  defmodule OutputCallbackAction do
    @moduledoc false
    use Action,
      name: "output_callback_action",
      description: "Action that uses output validation callbacks",
      output_schema: [
        value: [type: :integer, required: true]
      ]

    @impl true
    def run(%{input: input}, _context) do
      {:ok, %{value: input}}
    end

    @impl true
    def on_before_validate_output(output) do
      {:ok, Map.put(output, :preprocessed, true)}
    end

    @impl true
    def on_after_validate_output(output) do
      {:ok, Map.put(output, :postprocessed, true)}
    end
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
      compensation: [enabled: true, max_retries: 3, timeout: 50],
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

    def run(_params, _context), do: {:error, Error.execution_error("Exec failed")}
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
    @dialyzer {:nowarn_function, run: 2}
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

      {:ok, %{result: "Multi-process action completed"}}
    end
  end

  defmodule TaskAction do
    @moduledoc false
    use Action,
      name: "task_action",
      description: "Runs multiple concurrent tasks"

    def run(%{count: count, delay: delay, link_to_group?: link_to_group?}, context) do
      task_group = Map.get(context, :__task_group__)

      tasks =
        for _ <- 1..count do
          Task.Supervisor.async_nolink(Jido.TaskSupervisor, fn ->
            # Link to task group for cleanup
            if link_to_group? do
              Process.group_leader(self(), task_group)
            end

            Process.sleep(delay)
            {:ok, %{result: "Task completed"}}
          end)
        end

      try do
        results = Task.await_many(tasks, delay * 2)
        {:ok, %{results: results}}
      catch
        :exit, _ ->
          {:error, "Tasks failed to complete"}
      end
    end

    def run(_, context), do: run(%{count: 1, delay: 250}, context)
  end

  defmodule NakedTaskAction do
    @moduledoc false
    use Action,
      name: "naked_task_action",
      description: "Spawns tasks without linking into OTP"

    def run(%{count: count}, _context) do
      _pids =
        for _ <- 1..count do
          spawn(fn ->
            Process.sleep(:infinity)
          end)
        end

      {:ok, %{result: "Multi-process action completed"}}
    end

    def run(_, context), do: run(%{count: 1}, context)
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
      description: "Simulates a delay in action",
      schema: [
        delay: [type: :integer, default: 1000, doc: "Delay in milliseconds"]
      ]

    def run(%{delay: delay}, _context) do
      Process.sleep(delay)
      {:ok, %{result: "Async action completed"}}
    end
  end

  defmodule ContextAction do
    @moduledoc false
    use Action,
      name: "context_aware_action",
      description: "Uses context in its action",
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
    Simulates an action with configurable retry behavior.
    """
    use Action,
      name: "retry_action",
      description: "Simulates an action with configurable retry behavior",
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

      success("Exec completed")
    catch
      :throw, :cancelled -> failure("Exec cancelled")
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
        action: [type: :string, required: true]
      ]

    @max_requests 5
    # 1 minute in milliseconds
    @time_window 60_000

    def run(%{action: action}, _context) do
      case check_rate_limit() do
        :ok ->
          {:ok, %{result: "Exec '#{action}' executed successfully"}}

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

  defmodule IOAction do
    @moduledoc """
    Test action module that demonstrates various IO operations.

    Used for testing IO-related functionality within actions.
    """

    use Action,
      name: "io_action",
      description: "Showcases various IO operations",
      schema: [
        input: [type: :any, required: true, default: %{foo: "bar"}],
        operation: [type: {:in, [:puts, :inspect, :write]}, required: true]
      ]

    @impl true
    def run(%{input: _input, operation: :inspect} = params, _context) do
      # credo:disable-for-next-line Credo.Check.Warning.IoInspect
      IO.inspect(params, label: "IOAction")
      {:ok, params}
    end

    @impl true
    def run(%{input: input, operation: :puts}, _context) do
      IO.puts(input)
      {:ok, %{input: input}}
    end

    @impl true
    def run(%{input: input, operation: :write}, _context) do
      IO.write(input)
      {:ok, %{input: input}}
    end
  end

  defmodule EnqueueAction do
    @moduledoc false
    use Action,
      name: "enqueue_action",
      description: "Enqueues another action based on params",
      schema: [
        action: [type: :atom, required: true],
        params: [type: :map, default: %{}]
      ]

    def run(%{action: action, params: params}, _context) do
      directive = %Jido.Agent.Directive.Enqueue{
        action: action,
        params: params,
        context: %{}
      }

      {:ok, %{}, directive}
    end
  end

  defmodule RegisterAction do
    @moduledoc false
    use Action,
      name: "register_action",
      description: "Registers a new action module",
      schema: [
        action_module: [type: :atom, required: true]
      ]

    def run(%{action_module: action_module}, _context) do
      directive = %Jido.Agent.Directive.RegisterAction{
        action_module: action_module
      }

      {:ok, %{}, directive}
    end
  end

  defmodule DeregisterAction do
    @moduledoc false
    use Action,
      name: "deregister_action",
      description: "Deregisters an existing action module",
      schema: [
        action_module: [type: :atom, required: true]
      ]

    def run(%{action_module: action_module}, _context) do
      # Prevent deregistering this module
      if action_module == __MODULE__ do
        {:error, :cannot_deregister_self}
      else
        directive = %Jido.Agent.Directive.DeregisterAction{
          action_module: action_module
        }

        {:ok, %{}, directive}
      end
    end
  end

  defmodule SpawnChild do
    @moduledoc false
    use Action,
      name: "spawn_child",
      description: "Spawns a child process under the agent's supervisor",
      schema: [
        module: [type: :atom, required: true],
        args: [type: :any, required: true]
      ]

    def run(%{module: module, args: args}, _context) do
      directive = %Jido.Agent.Directive.Spawn{
        module: module,
        args: args
      }

      {:ok, %{}, directive}
    end
  end

  defmodule KillChild do
    @moduledoc false
    use Action,
      name: "kill_child",
      description: "Terminates a child process",
      schema: [
        pid: [type: :pid, required: true]
      ]

    def run(%{pid: pid}, _context) do
      directive = %Jido.Agent.Directive.Kill{
        pid: pid
      }

      {:ok, %{}, directive}
    end
  end

  defmodule ErrorDirective do
    @moduledoc false
    use Action,
      name: "error_directive",
      description: "Raises an error",
      schema: []

    def run(%{action: action, params: params}, _context) do
      directive = %Jido.Agent.Directive.Enqueue{
        action: action,
        params: params,
        context: %{}
      }

      {:error, Error.internal_server_error("Simulated error"), directive}
    end
  end

  defmodule FormatUser do
    @moduledoc false
    use Action,
      name: "format_user",
      description: "Formats user data",
      schema: [
        name: [type: :string, required: true, doc: "User's full name"],
        email: [type: :string, required: true, doc: "User's email address"],
        age: [type: :integer, required: true, doc: "User's age"]
      ]

    def run(params, _context) do
      %{name: name, email: email, age: age} = params

      {:ok,
       %{
         formatted_name: String.trim(name),
         email: String.downcase(email),
         age: age,
         is_adult: age >= 18
       }}
    end
  end

  defmodule EnrichUserData do
    @moduledoc false
    use Action,
      name: "enrich_user_data",
      description: "Adds additional user information",
      schema: [
        formatted_name: [type: :string, required: true],
        email: [type: :string, required: true]
      ]

    def run(%{formatted_name: name, email: email}, _context) do
      {:ok,
       %{
         username: generate_username(name),
         avatar_url: get_gravatar_url(email)
       }}
    end

    defp generate_username(name) do
      name
      |> String.downcase()
      |> String.replace(" ", ".")
    end

    defp get_gravatar_url(email) do
      hash = :crypto.hash(:md5, email) |> Base.encode16(case: :lower)
      "https://www.gravatar.com/avatar/#{hash}"
    end
  end

  defmodule NotifyUser do
    @moduledoc false
    use Action,
      name: "notify_user",
      description: "Sends welcome notification to user",
      schema: [
        email: [type: :string, required: true],
        username: [type: :string, required: true]
      ]

    def run(%{email: email, username: username}, _context) do
      # In a real app, you'd send an actual email
      {:ok,
       %{
         notification_sent: true,
         notification_type: "welcome_email",
         recipient: %{
           email: email,
           username: username
         }
       }}
    end
  end

  defmodule FormatEnrichNotifyUserChain do
    @moduledoc false
    use Action,
      name: "format_enrich_notify_user_chain",
      description: "Demonstrate how an action can package a chain of actions",
      schema: [
        name: [type: :string, required: true],
        email: [type: :string, required: true],
        age: [type: :integer, required: true]
      ]

    def run(params, _context) do
      Jido.Exec.Chain.chain(
        [
          JidoTest.TestActions.FormatUser,
          JidoTest.TestActions.EnrichUserData,
          JidoTest.TestActions.NotifyUser
        ],
        params
      )
    end
  end

  defmodule MultiDirectiveAction do
    @moduledoc false
    use Jido.Action,
      name: "multi_directive_action"

    alias Jido.Agent.Directive.{Enqueue, Spawn, Kill}

    @impl true
    def run(%{type: :agent}, _context) do
      directives = [
        %Enqueue{
          action: JidoTest.TestActions.NoSchema,
          params: %{value: 1},
          context: %{}
        },
        %Enqueue{
          action: JidoTest.TestActions.Add,
          params: %{value: 3, amount: 1},
          context: %{}
        }
      ]

      {:ok, %{}, directives}
    end

    def run(%{type: :server}, _context) do
      directives = [
        %Spawn{
          module: __MODULE__,
          args: []
        },
        %Kill{
          pid: self()
        }
      ]

      {:ok, %{}, directives}
    end

    def run(%{type: :mixed}, _context) do
      directives = [
        %Enqueue{
          action: :action1,
          params: %{},
          context: %{}
        },
        %Spawn{
          module: __MODULE__,
          args: []
        }
      ]

      {:ok, %{}, directives}
    end

    def run(_params, _context) do
      # Default to agent directives for backwards compatibility
      run(%{type: :agent}, %{})
    end
  end

  defmodule StateCheckAction do
    @moduledoc false
    use Action,
      name: "state_check_action",
      description: "Verifies state is injected into context"

    def run(_params, context) do
      {:ok, %{state_in_context: context.state}}
    end
  end

  defmodule Echo do
    @moduledoc false

    @doc """
    Simple echo action that returns its input parameters.
    """
    def run(params, _context, _opts) do
      {:ok, params}
    end
  end

  defmodule ReturnInstructionAction do
    @moduledoc "Test action that returns an instruction as a directive"
    use Action,
      name: "return_instruction_action",
      description: "Returns a single instruction as a directive"

    def run(_params, _context) do
      next_instruction = %Instruction{
        action: __MODULE__,
        params: %{value: 42},
        context: %{}
      }

      {:ok, %{}, next_instruction}
    end
  end

  defmodule ReturnInstructionListAction do
    @moduledoc "Test action that returns a list of instructions as directives"
    use Action,
      name: "return_instruction_list_action",
      description: "Returns a list of instructions as directives"

    def run(_params, _context) do
      instructions = [
        %Instruction{
          action: ReturnInstructionAction,
          params: %{value: 1},
          context: %{}
        },
        %Instruction{
          action: ReturnInstructionAction,
          params: %{value: 2},
          context: %{}
        }
      ]

      {:ok, %{}, instructions}
    end
  end

  defmodule MetadataAction do
    @moduledoc false
    use Action,
      name: "metadata_action",
      description: "Demonstrates action metadata",
      vsn: "87.52.1",
      schema: []

    def run(_params, context) do
      {:ok, %{metadata: context.action_metadata}}
    end
  end
end
