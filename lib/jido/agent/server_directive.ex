defmodule Jido.Agent.Server.Directive do
  @moduledoc false
  use ExDbug, enabled: false
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.Process, as: ServerProcess
  alias Jido.Instruction

  alias Jido.Agent.Directive.{
    Spawn,
    Kill,
    Enqueue,
    RegisterAction,
    DeregisterAction,
    StateModification
  }

  alias Jido.{Agent.Directive, Error}

  @doc """
  Processes one or more directives against a server state.

  Takes a ServerState and a list of directives, executing each in sequence and
  returning the final updated state.

  ## Parameters
    - state: Current server state
    - directives: Single directive or list of directives to process

  ## Returns
    - `{:ok, updated_state}` - All directives executed successfully
    - `{:error, Error.t()}` - Failed to execute a directive

  ## Examples

      # Process a single directive
      {:ok, state} = Directive.handle(state, %Spawn{module: MyWorker})

      # Process multiple directives
      {:ok, state} = Directive.handle(state, [
        %Spawn{module: Worker1},
        %Spawn{module: Worker2}
      ])
  """
  @spec handle(ServerState.t(), Directive.t() | [Directive.t()]) ::
          {:ok, ServerState.t()} | {:error, term()}
  def handle(%ServerState{} = state, directives) when is_list(directives) do
    dbug("Processing multiple directives", directives: directives)

    Enum.reduce_while(directives, {:ok, state}, fn directive, {:ok, acc_state} ->
      case execute(acc_state, directive) do
        {:ok, new_state} ->
          dbug("Directive executed successfully", directive: directive)
          {:cont, {:ok, new_state}}

        {:error, _} = error ->
          dbug("Directive execution failed", directive: directive, error: error)
          {:halt, error}
      end
    end)
  end

  def handle(%ServerState{} = state, directive) do
    dbug("Processing single directive", directive: directive)
    execute(state, directive)
  end

  @doc """
  Executes a validated directive within a server context.

  Takes a ServerState and a Directive struct, and applies the directive's operation
  to modify the server state appropriately.

  ## Parameters
    - state: Current server state
    - directive: The directive to execute

  ## Returns
    - `{:ok, updated_state}` - Directive executed successfully
    - `{:error, Error.t()}` - Failed to execute directive

  ## Examples

      # Execute a spawn directive
      {:ok, state} = Directive.execute(state, %Spawn{module: MyWorker, args: [id: 1]})

      # Execute a kill directive
      {:ok, state} = Directive.execute(state, %Kill{pid: worker_pid})
  """
  @spec execute(ServerState.t(), Directive.t()) :: {:ok, ServerState.t()} | {:error, term()}

  # Kill directive - should come before Spawn to avoid pattern overlap
  def execute(%ServerState{} = state, %Kill{pid: pid}) do
    dbug("Executing kill directive", pid: pid)

    case ServerProcess.terminate(state, pid) do
      :ok ->
        dbug("Process terminated successfully", pid: pid)
        {:ok, state}

      {:error, :not_found} ->
        dbug("Process not found", pid: pid)
        {:error, Error.execution_error("Process not found", %{pid: pid})}
    end
  end

  # Spawn directive for Task with function
  def execute(%ServerState{} = state, %Spawn{module: Task, args: fun}) when is_function(fun) do
    dbug("Executing spawn task directive", fun: fun)

    # Create a proper child spec for Task
    child_spec = %{
      id: make_ref(),
      start: {Task, :start_link, [fun]},
      restart: :temporary,
      type: :worker
    }

    case ServerProcess.start(state, child_spec) do
      {:ok, updated_state, _pid} ->
        dbug("Task spawned successfully: pid: #{inspect(_pid)}")
        {:ok, updated_state}

      {:error, reason} ->
        dbug("Failed to spawn task", reason: reason)
        {:error, Error.execution_error("Failed to spawn process", %{reason: reason})}
    end
  end

  # Spawn directive for general modules  
  def execute(%ServerState{} = state, %Spawn{module: module, args: args}) do
    dbug("Executing spawn directive", module: module, args: args)

    case ServerProcess.start(state, {module, args}) do
      {:ok, updated_state, _pid} ->
        dbug("Process spawned successfully: pid: #{inspect(_pid)}")
        {:ok, updated_state}

      {:error, reason} ->
        dbug("Failed to spawn process", reason: reason)
        {:error, Error.execution_error("Failed to spawn process", %{reason: reason})}
    end
  end

  def execute(%ServerState{} = state, %Enqueue{
        action: action,
        params: params,
        context: context,
        opts: opts
      }) do
    dbug("Executing enqueue directive", action: action, params: params)

    # Validate action is not nil  
    cond do
      action == nil ->
        {:error, Error.validation_error("Action cannot be nil", %{action: action})}

      not is_atom(action) ->
        {:error, Error.validation_error("Action must be an atom", %{action: action})}

      true ->
        # Create instruction from directive
        instruction = %Instruction{action: action, params: params, context: context, opts: opts}

        # Create signal with instruction as data
        signal = ServerSignal.cmd_signal(:enqueue, state, instruction)

        dbug("Processing enqueue directive", signal: signal)

        # Enqueue signal at front of queue
        case ServerState.enqueue_front(state, signal) do
          {:ok, updated_state} ->
            dbug("Signal enqueued successfully")
            {:ok, updated_state}

          {:error, :queue_overflow} ->
            dbug("Failed to enqueue signal - queue overflow")

            {:error,
             Error.execution_error("Failed to enqueue signal", %{reason: :queue_overflow})}
        end
    end
  end

  def execute(%ServerState{} = state, %RegisterAction{action_module: module}) do
    dbug("Executing register action directive", module: module)

    # Add action module to agent's actions list if not already present
    if module in state.agent.actions do
      dbug("Action module already registered", module: module)
      {:ok, state}
    else
      dbug("Registering action module", module: module)
      updated_agent = %{state.agent | actions: [module | state.agent.actions]}
      {:ok, %{state | agent: updated_agent}}
    end
  end

  def execute(%ServerState{} = state, %DeregisterAction{action_module: module}) do
    dbug("Executing deregister action directive", module: module)

    # Remove action module from agent's actions list
    updated_agent = %{state.agent | actions: List.delete(state.agent.actions, module)}
    {:ok, %{state | agent: updated_agent}}
  end

  def execute(%ServerState{} = state, %StateModification{op: op, path: path, value: value}) do
    dbug("Executing state modification directive", op: op, path: path, value: value)

    try do
      case op do
        :set ->
          updated_agent = %{
            state.agent
            | state: put_in(state.agent.state, List.wrap(path), value)
          }

          {:ok, %{state | agent: updated_agent}}

        :update when is_function(value) ->
          updated_agent = %{
            state.agent
            | state: update_in(state.agent.state, List.wrap(path), value)
          }

          {:ok, %{state | agent: updated_agent}}

        :delete ->
          {_, updated_state} = pop_in(state.agent.state, List.wrap(path))
          updated_agent = %{state.agent | state: updated_state}
          {:ok, %{state | agent: updated_agent}}

        :reset ->
          updated_agent = %{state.agent | state: put_in(state.agent.state, List.wrap(path), nil)}
          {:ok, %{state | agent: updated_agent}}

        # Handle test cases and potential runtime type bypassing
        invalid_op ->
          dbug("Invalid state modification operation", op: invalid_op)

          {:error,
           Error.validation_error("Invalid state modification operation", %{op: invalid_op})}
      end
    rescue
      error in [ArgumentError] ->
        dbug("Failed to modify state", error: error)
        {:error, Error.execution_error("Failed to modify state", %{error: error})}
    end
  end

  def execute(_state, invalid_directive) do
    dbug("Invalid directive received", directive: invalid_directive)
    {:error, Error.validation_error("Invalid directive", %{directive: invalid_directive})}
  end
end
