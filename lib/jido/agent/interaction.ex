defmodule Jido.Agent.Interaction do
  @moduledoc """
  Agent interaction functions for synchronous and asynchronous communication.

  This module provides the core agent communication primitives including:
  - `call/3` - Synchronous agent communication
  - `cast/2` - Asynchronous agent communication
  - `send_signal/4` - Signal construction and dispatch
  - `send_instruction/4` - Instruction construction and dispatch  
  - `request/4` - Unified request interface

  All functions support agent reference resolution from PIDs, IDs, or `{:ok, pid}` tuples.

  ## Usage

      # Synchronous call with Signal
      signal = %Jido.Signal{type: "get_status", data: %{}}
      {:ok, status} = Jido.Agent.Interaction.call("worker-1", signal)

      # Asynchronous cast with Instruction
      instruction = %Jido.Instruction{action: "log_event", params: %{event: "started"}}
      {:ok, signal_id} = Jido.Agent.Interaction.cast("worker-1", instruction)

      # High-level request interface
      {:ok, result} = Jido.Agent.Interaction.request("worker-1", "calculate", %{formula: "2+2"})
  """

  @type agent_id :: String.t() | atom()
  @type agent_ref :: pid() | {:ok, pid()} | agent_id()

  @doc """
  Sends a synchronous call to an agent and waits for a response.

  Thin delegate to `Jido.Agent.Server.call/3` with automatic PID resolution.
  Supports both Signal and Instruction structs for communication.

  ## Parameters

  - `agent_ref`: Agent PID, ID, or `{:ok, pid}` tuple
  - `message`: Signal or Instruction struct to send
  - `timeout`: Timeout in milliseconds (default: 5000)

  ## Returns

  - `{:ok, result}` - Successful response from agent
  - `{:error, reason}` - Call failed or timed out

  ## Examples

      # Call with Signal
      signal = %Jido.Signal{type: "get_status", data: %{}}
      {:ok, status} = Jido.Agent.Interaction.call("worker-1", signal)

      # Call with Instruction  
      instruction = %Jido.Instruction{action: "process_data", params: %{id: 123}}
      {:ok, result} = Jido.Agent.Interaction.call("worker-1", instruction, 10_000)

      # Pipe-friendly usage
      "worker-1"
      |> Jido.Agent.Lifecycle.get_agent()
      |> Jido.Agent.Interaction.call(%Jido.Signal{type: "ping"})
  """
  @spec call(agent_ref(), struct(), pos_integer()) :: {:ok, term()} | {:error, term()}
  def call(agent_ref, message, timeout \\ 5000)

  def call({:ok, pid}, message, timeout), do: call(pid, message, timeout)

  def call(pid, message, timeout) when is_pid(pid) do
    Jido.Agent.Server.call(pid, message, timeout)
  end

  def call(id, message, timeout) when is_binary(id) or is_atom(id) do
    case Jido.Agent.Lifecycle.get_agent(id) do
      {:ok, pid} -> call(pid, message, timeout)
      error -> error
    end
  end

  @doc """
  Sends an asynchronous cast to an agent without waiting for response.

  Thin delegate to `Jido.Agent.Server.cast/2` with automatic PID resolution.
  Fire-and-forget messaging for non-blocking agent communication.

  ## Parameters

  - `agent_ref`: Agent PID, ID, or `{:ok, pid}` tuple  
  - `message`: Signal or Instruction struct to send

  ## Returns

  - `{:ok, signal_id}` - Message sent successfully, returns tracking ID
  - `{:error, reason}` - Cast failed

  ## Examples

      # Cast with Signal
      signal = %Jido.Signal{type: "background_task", data: %{priority: :low}}
      {:ok, signal_id} = Jido.Agent.Interaction.cast("worker-1", signal)

      # Cast with Instruction
      instruction = %Jido.Instruction{action: "log_event", params: %{event: "started"}}
      {:ok, signal_id} = Jido.Agent.Interaction.cast("worker-1", instruction)

      # Pipe-friendly usage
      "worker-1" |> Jido.Agent.Lifecycle.get_agent() |> Jido.Agent.Interaction.cast(%Jido.Signal{type: "notify"})
  """
  @spec cast(agent_ref(), struct()) :: {:ok, String.t()} | {:error, term()}
  def cast(agent_ref, message)

  def cast({:ok, pid}, message), do: cast(pid, message)

  def cast(pid, message) when is_pid(pid) do
    Jido.Agent.Server.cast(pid, message)
  end

  def cast(id, message) when is_binary(id) or is_atom(id) do
    case Jido.Agent.Lifecycle.get_agent(id) do
      {:ok, pid} -> cast(pid, message)
      error -> error
    end
  end

  @doc """
  Builds a Signal struct from components and dispatches it via cast.

  Convenience function that constructs a Signal struct from type and data
  parameters, then sends it asynchronously to the agent.

  ## Parameters

  - `agent_ref`: Agent PID, ID, or `{:ok, pid}` tuple
  - `type`: Signal type string
  - `data`: Signal data map
  - `opts`: Optional signal options:
    - `:source` - Signal source identifier
    - `:subject` - Signal subject
    - `:dispatch` - Dispatch configuration (via extensions)
    - Other Signal fields (see `Jido.Signal`)

  ## Returns

  - `{:ok, signal_id}` - Signal sent successfully
  - `{:error, reason}` - Failed to send signal

  ## Examples

      # Simple signal
      {:ok, signal_id} = Jido.Agent.Interaction.send_signal("worker-1", "process", %{item_id: 123})

      # Signal with options
      {:ok, signal_id} = Jido.Agent.Interaction.send_signal("worker-1", "urgent_task", %{priority: :high}, 
        source: "api_server",
        subject: "task_processor"
      )

      # Pipe-friendly usage
      "worker-1" |> Jido.Agent.Interaction.send_signal("notify", %{message: "Hello"})
  """
  @spec send_signal(agent_ref(), String.t(), map(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_signal(agent_ref, type, data, opts \\ []) do
    with {:ok, signal} <- build_signal(type, data, opts) do
      cast(agent_ref, signal)
    end
  end

  @doc """
  Builds an Instruction struct from components and dispatches it via cast.

  Convenience function that constructs an Instruction struct from action and
  params, then sends it asynchronously to the agent.

  ## Parameters

  - `agent_ref`: Agent PID, ID, or `{:ok, pid}` tuple
  - `action`: Action name string or atom
  - `params`: Action parameters map
  - `opts`: Optional instruction options:
    - `:context` - Instruction context map
    - `:timeout` - Instruction timeout
    - `:priority` - Instruction priority
    - Other Instruction fields (see `Jido.Instruction`)

  ## Returns

  - `{:ok, signal_id}` - Instruction sent successfully  
  - `{:error, reason}` - Failed to send instruction

  ## Examples

      # Simple instruction
      {:ok, signal_id} = Jido.Agent.Interaction.send_instruction("worker-1", "calculate", %{formula: "2+2"})

      # Instruction with context
      {:ok, signal_id} = Jido.Agent.Interaction.send_instruction("worker-1", "process_order", %{order_id: 123},
        context: %{user_id: "user-456", session: "sess-789"},
        priority: :high
      )

      # Pipe-friendly usage  
      "worker-1" |> Jido.Agent.Interaction.send_instruction("validate", %{data: payload})
  """
  @spec send_instruction(agent_ref(), String.t() | atom(), map(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_instruction(agent_ref, action, params, opts \\ []) do
    with {:ok, instruction} <- build_instruction(action, params, opts) do
      cast(agent_ref, instruction)
    end
  end

  @doc """
  High-level unified request interface for agent communication.

  Converts requests to Instruction or Signal structs based on the `:type` option,
  then dispatches synchronously or asynchronously based on the `:mode` option.
  This is often the only function applications need for agent interaction.

  ## Parameters

  - `agent_ref`: Agent PID, ID, or `{:ok, pid}` tuple
  - `path`: Request path or action name
  - `payload`: Request payload/parameters map
  - `opts`: Request options:
    - `:type` - `:signal` or `:instruction` (default: `:instruction`)
    - `:mode` - `:sync` or `:async` (default: `:sync`)
    - `:timeout` - Timeout for synchronous requests (default: 5000)
    - Other options passed to underlying Signal/Instruction

  ## Returns

  - **Synchronous mode**: `{:ok, result}` | `{:error, reason}`
  - **Asynchronous mode**: `{:ok, signal_id}` | `{:error, reason}`

  ## Examples

      # Synchronous instruction (default)
      {:ok, result} = Jido.Agent.Interaction.request("worker-1", "calculate", %{formula: "2+2"})

      # Asynchronous signal
      {:ok, signal_id} = Jido.Agent.Interaction.request("worker-1", "background_job", %{data: payload}, 
        type: :signal, 
        mode: :async
      )

      # Synchronous signal with timeout
      {:ok, status} = Jido.Agent.Interaction.request("worker-1", "get_status", %{}, 
        type: :signal,
        mode: :sync,
        timeout: 10_000
      )

      # Pipe-friendly usage
      result = "worker-1" |> Jido.Agent.Interaction.request("process", %{id: 123}) |> elem(1)
  """
  @spec request(agent_ref(), String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def request(agent_ref, path, payload, opts \\ []) do
    type = Keyword.get(opts, :type, :instruction)
    mode = Keyword.get(opts, :mode, :sync)
    timeout = Keyword.get(opts, :timeout, 5000)

    # Remove request-specific options before passing to build functions
    build_opts = Keyword.drop(opts, [:type, :mode, :timeout])

    with {:ok, message} <- build_message(type, path, payload, build_opts) do
      case mode do
        :sync -> call(agent_ref, message, timeout)
        :async -> cast(agent_ref, message)
        _ -> {:error, {:invalid_mode, mode}}
      end
    end
  end

  # Private helper functions

  defp build_signal(type, data, opts) do
    signal_attrs = %{
      type: type,
      data: data
    }

    # Extract dispatch config (support both :dispatch and legacy :jido_dispatch)
    dispatch_config = Keyword.get(opts, :dispatch) || Keyword.get(opts, :jido_dispatch)

    # Add optional CloudEvents-compliant fields if provided in opts
    final_attrs =
      opts
      |> Enum.reduce(signal_attrs, fn {key, value}, acc ->
        case key do
          key when key in [:source, :subject, :time, :datacontenttype, :dataschema] ->
            Map.put(acc, key, value)

          _ ->
            acc
        end
      end)

    with {:ok, signal} <- Jido.Signal.new(final_attrs) do
      if dispatch_config do
        Jido.Signal.DispatchHelpers.put_dispatch(signal, dispatch_config)
      else
        {:ok, signal}
      end
    end
  end

  defp build_instruction(action, params, opts) do
    # Extract Instruction-specific options
    {instruction_opts, other_opts} =
      Keyword.split(opts, [:context, :id])

    attrs = %{
      action: normalize_action(action),
      params: params || %{}
    }

    # Add optional fields
    final_attrs =
      instruction_opts
      |> Enum.reduce(attrs, fn {key, value}, acc ->
        Map.put(acc, key, value)
      end)
      |> Map.put(:opts, other_opts)

    Jido.Instruction.new(final_attrs)
  end

  defp build_message(:signal, path, payload, opts) do
    build_signal(path, payload, opts)
  end

  defp build_message(:instruction, path, payload, opts) do
    build_instruction(path, payload, opts)
  end

  defp build_message(invalid_type, _path, _payload, _opts) do
    {:error, {:invalid_type, invalid_type}}
  end

  defp normalize_action(action) when is_binary(action) do
    String.to_existing_atom(action)
  rescue
    ArgumentError -> action
  end

  defp normalize_action(action) when is_atom(action), do: action
  defp normalize_action(action), do: action
end
