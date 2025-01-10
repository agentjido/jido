defmodule Jido.Agent.Directive do
  @moduledoc """
    Provides a type-safe way to modify agent state through discrete, validated directives.

    ## Overview

    Directives are immutable instructions that can be applied to an agent to modify its state
    in predefined ways. Each directive type is implemented as a separate struct with its own
    validation rules, helping ensure type safety and consistent state transitions.

    ## Available Directives

    * `EnqueueDirective` - Adds a new instruction to the agent's pending queue
        - Requires an action atom
        - Supports optional params and context maps
        - Supports optional opts keyword list
        - Example: `%EnqueueDirective{action: :move, params: %{location: :kitchen}}`

    * `RegisterActionDirective` - Registers a new action module with the agent
        - Requires a valid module atom
        - Example: `%RegisterActionDirective{action_module: MyApp.Actions.Move}`

    * `DeregisterActionDirective` - Removes an action module from the agent
        - Requires a valid module atom
        - Example: `%DeregisterActionDirective{action_module: MyApp.Actions.Move}`

    * `SpawnDirective` - Spawns a child process under the agent's supervisor
        - Requires a module atom and arguments
        - Example: `%SpawnDirective{module: MyWorker, args: [id: 1]}`

    * `KillDirective` - Terminates a child process
        - Requires a valid PID
        - Example: `%KillDirective{pid: #PID<0.123.0>}`

    * `PublishDirective` - Broadcasts a message on a PubSub topic
        - Requires a topic string and message
        - Example: `%PublishDirective{topic: "events", message: %{type: :update}}`

    * `SubscribeDirective` - Subscribes to a PubSub topic
        - Requires a topic string
        - Example: `%SubscribeDirective{topic: "events"}`

    * `UnsubscribeDirective` - Unsubscribes from a PubSub topic
        - Requires a topic string
        - Example: `%UnsubscribeDirective{topic: "events"}`

    ## Usage

    Directives are typically created by action handlers and applied through the `apply_agent_directives/3`
    function. The function processes directives in order and ensures atomicity - if any directive
    fails, the entire operation is rolled back.

    ```elixir
    # Single directive
    directive = %EnqueueDirective{action: :move, params: %{location: :kitchen}}
    result = %Result{directives: [directive]}
    {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

    # Multiple directives
    directives = [
      %RegisterActionDirective{action_module: MyApp.Actions.Move},
      %EnqueueDirective{action: :move, params: %{location: :kitchen}}
    ]

    result = %Result{directives: directives}
    {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)
    ```

    ## Validation

    Each directive type has its own validation rules:

    * `EnqueueDirective` requires a non-nil atom for the action
    * `RegisterActionDirective` requires a valid module atom
    * `DeregisterActionDirective` requires a valid module atom
    * `SpawnDirective` requires a valid module atom and arguments
    * `KillDirective` requires a valid PID
    * `PublishDirective` requires a valid topic string and message
    * `SubscribeDirective` requires a valid topic string
    * `UnsubscribeDirective` requires a valid topic string

    Failed validation results in an error tuple being returned and processing being halted.

    ## Error Handling

    The module uses tagged tuples for error handling:

    * `{:ok, updated_agent}` - Successful application of directives
    * `{:error, reason}` - Failed validation or application

    Common error reasons include:

    * `:invalid_action` - The action specified in an `EnqueueDirective` is invalid
    * `:invalid_action_module` - The module specified in a `Register/DeregisterDirective` is invalid
    * `:invalid_module` - The module specified in a `SpawnDirective` is invalid
    * `:invalid_pid` - The PID specified in a `KillDirective` is invalid
    * `:invalid_topic` - The topic specified in a broadcast/subscribe/unsubscribe directive is invalid
  """
  use ExDbug, enabled: false
  use TypedStruct
  alias Jido.Agent
  alias Jido.Runner.Result
  alias Jido.Instruction

  typedstruct module: EnqueueDirective do
    @moduledoc "Directive to enqueue a new instruction"
    field(:action, atom(), enforce: true)
    field(:params, map(), default: %{})
    field(:context, map(), default: %{})
    field(:opts, keyword(), default: [])
  end

  typedstruct module: RegisterActionDirective do
    @moduledoc "Directive to register a new action module"
    field(:action_module, module(), enforce: true)
  end

  typedstruct module: DeregisterActionDirective do
    @moduledoc "Directive to deregister an existing action module"
    field(:action_module, module(), enforce: true)
  end

  typedstruct module: SpawnDirective do
    @moduledoc "Directive to spawn a child process"
    field(:module, module(), enforce: true)
    field(:args, term(), enforce: true)
  end

  typedstruct module: KillDirective do
    @moduledoc "Directive to terminate a child process"
    field(:pid, pid(), enforce: true)
  end

  typedstruct module: PublishDirective do
    @moduledoc "Directive to broadcast a message"
    field(:stream_id, String.t(), enforce: true)
    field(:signal, term(), enforce: true)
  end

  typedstruct module: SubscribeDirective do
    @moduledoc "Directive to subscribe to a topic"
    field(:stream_id, String.t(), enforce: true)
  end

  typedstruct module: UnsubscribeDirective do
    @moduledoc "Directive to unsubscribe from a topic"
    field(:stream_id, String.t(), enforce: true)
  end

  @type t ::
          EnqueueDirective.t()
          | RegisterActionDirective.t()
          | DeregisterActionDirective.t()
          | SpawnDirective.t()
          | KillDirective.t()
          | PublishDirective.t()
          | SubscribeDirective.t()
          | UnsubscribeDirective.t()

  @type directive_result :: {:ok, Agent.t()} | {:error, term()}

  @doc """
  Checks if a value is a valid directive struct or ok-tupled directive.

  A valid directive is either:
  - A struct of type EnqueueDirective, RegisterActionDirective, or DeregisterActionDirective
  - An ok-tuple containing one of the above directive structs

  ## Parameters
    - value: Any value to check

  ## Returns
    - `true` if the value is a valid directive
    - `false` otherwise

  ## Examples

      iex> is_directive?(%EnqueueDirective{action: :test})
      true

      iex> is_directive?({:ok, %RegisterActionDirective{action_module: MyModule}})
      true

      iex> is_directive?(:not_a_directive)
      false
  """
  @spec is_directive?(term()) :: boolean()
  def is_directive?({:ok, directive}) when is_struct(directive, EnqueueDirective), do: true
  def is_directive?({:ok, directive}) when is_struct(directive, RegisterActionDirective), do: true

  def is_directive?({:ok, directive}) when is_struct(directive, DeregisterActionDirective),
    do: true

  def is_directive?({:ok, directive}) when is_struct(directive, SpawnDirective), do: true
  def is_directive?({:ok, directive}) when is_struct(directive, KillDirective), do: true
  def is_directive?({:ok, directive}) when is_struct(directive, PublishDirective), do: true
  def is_directive?({:ok, directive}) when is_struct(directive, SubscribeDirective), do: true
  def is_directive?({:ok, directive}) when is_struct(directive, UnsubscribeDirective), do: true

  def is_directive?(directive) when is_struct(directive, EnqueueDirective), do: true
  def is_directive?(directive) when is_struct(directive, RegisterActionDirective), do: true
  def is_directive?(directive) when is_struct(directive, DeregisterActionDirective), do: true
  def is_directive?(directive) when is_struct(directive, SpawnDirective), do: true
  def is_directive?(directive) when is_struct(directive, KillDirective), do: true
  def is_directive?(directive) when is_struct(directive, PublishDirective), do: true
  def is_directive?(directive) when is_struct(directive, SubscribeDirective), do: true
  def is_directive?(directive) when is_struct(directive, UnsubscribeDirective), do: true
  def is_directive?(_), do: false

  @doc """
  Applies a list of directives to an agent, maintaining ordering and atomicity.
  Returns either the updated agent or an error if any directive application fails.

  ## Parameters
    - agent: The agent struct to apply directives to
    - result: A Result struct containing the list of directives to apply
    - opts: Optional keyword list of options (default: [])

  ## Returns
    - `{:ok, updated_agent}` - All directives were successfully applied
    - `{:error, reason}` - A directive failed to apply, with reason for failure

  ## Examples

      result = %Result{directives: [
        %EnqueueDirective{action: :my_action, params: %{key: "value"}},
        %RegisterActionDirective{action_module: MyAction}
      ]}

      {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

  ## Behavior
  - Applies directives in order, stopping on first error
  - Maintains atomicity - all directives succeed or none are applied
  - Logs debug info about directive application
  """
  def apply_agent_directives(agent, %Result{directives: directives}, opts \\ []) do
    dbug("Applying #{length(directives)} directives to agent #{agent.id}",
      agent_id: agent.id,
      directive_count: length(directives)
    )

    {agent, _completed_instruction} =
      case :queue.out(agent.pending_instructions) do
        {{:value, instruction}, remaining_queue} ->
          {%{agent | pending_instructions: remaining_queue}, instruction}

        {:empty, _} ->
          {agent, nil}
      end

    # Now process the directives
    Enum.reduce_while(directives, {:ok, agent}, fn directive, {:ok, current_agent} ->
      case apply_agent_directive(current_agent, directive, opts) do
        {:ok, updated_agent} ->
          {:cont, {:ok, updated_agent}}

        {:error, _reason} = error ->
          dbug("Failed to apply directive",
            agent: agent,
            directive: directive,
            reason: error
          )

          {:halt, error}
      end
    end)
  end

  @doc """
  Applies a single directive to an agent. Pattern matches on directive type
  to execute the appropriate transformation.

  ## Parameters
    - agent: The agent struct to apply the directive to
    - directive: The directive struct to apply
    - opts: Optional keyword list of options (default: [])

  ## Returns
    - `{:ok, updated_agent}` - Directive was successfully applied
    - `{:error, reason}` - Failed to apply directive with reason

  ## Directive Types

  ### EnqueueDirective
  Adds a new instruction to the agent's pending queue.

  ### RegisterActionDirective
  Registers a new action module with the agent.

  ### DeregisterActionDirective
  Removes an action module from the agent.

  ### SpawnDirective
  Spawns a child process under the agent's supervisor.

  ### KillDirective
  Terminates a child process.

  ### PublishDirective
  Broadcasts a message on a PubSub topic.

  ### SubscribeDirective
  Subscribes to a PubSub topic.

  ### UnsubscribeDirective
  Unsubscribes from a PubSub topic.
  """
  @spec apply_agent_directive(Agent.t(), t(), keyword()) :: directive_result()
  def apply_agent_directive(agent, %EnqueueDirective{} = directive, _opts) do
    case validate_enqueue_directive(directive) do
      :ok ->
        instruction = build_instruction(directive)
        new_queue = :queue.in(instruction, agent.pending_instructions)

        dbug("Enqueued new instruction",
          agent_id: agent.id,
          action: directive.action
        )

        {:ok, %{agent | pending_instructions: new_queue}}

      {:error, _reason} = error ->
        error
    end
  end

  def apply_agent_directive(agent, %RegisterActionDirective{} = directive, _opts) do
    case validate_register_directive(directive) do
      :ok ->
        dbug("Registering action module",
          agent_id: agent.id,
          module: directive.action_module
        )

        Agent.register_action(agent, directive.action_module)

      {:error, _reason} = error ->
        error
    end
  end

  def apply_agent_directive(agent, %DeregisterActionDirective{} = directive, _opts) do
    case validate_deregister_directive(directive) do
      :ok ->
        dbug("Deregistering action module",
          agent_id: agent.id,
          module: directive.action_module
        )

        Agent.deregister_action(agent, directive.action_module)

      {:error, _reason} = error ->
        error
    end
  end

  @spec validate_syscall(t()) :: :ok | {:error, term()}
  def validate_syscall(%SpawnDirective{module: nil}), do: {:error, :invalid_module}
  def validate_syscall(%SpawnDirective{module: mod}) when is_atom(mod), do: :ok

  def validate_syscall(%KillDirective{pid: pid}) when is_pid(pid), do: :ok
  def validate_syscall(%KillDirective{}), do: {:error, :invalid_pid}

  def validate_syscall(%PublishDirective{stream_id: stream_id}) when is_binary(stream_id),
    do: :ok

  def validate_syscall(%PublishDirective{}), do: {:error, :invalid_stream_id}

  def validate_syscall(%SubscribeDirective{stream_id: stream_id}) when is_binary(stream_id),
    do: :ok

  def validate_syscall(%SubscribeDirective{}), do: {:error, :invalid_stream_id}

  def validate_syscall(%UnsubscribeDirective{stream_id: stream_id}) when is_binary(stream_id),
    do: :ok

  def validate_syscall(%UnsubscribeDirective{}), do: {:error, :invalid_stream_id}

  def validate_syscall(_), do: {:error, :invalid_syscall}
  defp validate_enqueue_directive(%EnqueueDirective{action: nil}), do: {:error, :invalid_action}
  defp validate_enqueue_directive(%EnqueueDirective{action: action}) when is_atom(action), do: :ok
  defp validate_enqueue_directive(_), do: {:error, :invalid_action}

  defp validate_register_directive(%RegisterActionDirective{action_module: module})
       when is_atom(module),
       do: :ok

  defp validate_register_directive(_), do: {:error, :invalid_action_module}

  defp validate_deregister_directive(%DeregisterActionDirective{action_module: module})
       when is_atom(module),
       do: :ok

  defp validate_deregister_directive(_), do: {:error, :invalid_action_module}

  defp build_instruction(%EnqueueDirective{action: action, params: params, context: context}) do
    %Instruction{action: action, params: params, context: context}
  end
end
