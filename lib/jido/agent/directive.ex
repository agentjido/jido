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
        - Example: `%EnqueueDirective{action: :move, params: %{location: :kitchen}}`

    * `RegisterActionDirective` - Registers a new action module with the agent
        - Requires a valid module atom
        - Example: `%RegisterActionDirective{action_module: MyApp.Actions.Move}`

    * `DeregisterActionDirective` - Removes an action module from the agent
        - Requires a valid module atom
        - Example: `%DeregisterActionDirective{action_module: MyApp.Actions.Move}`

    ## Usage

    Directives are typically created by action handlers and applied through the `apply_directives/3`
    function. The function processes directives in order and ensures atomicity - if any directive
    fails, the entire operation is rolled back.

    ```elixir
    # Single directive
    directive = %EnqueueDirective{action: :move, params: %{location: :kitchen}}
    result = %Result{directives: [directive]}
    {:ok, updated_agent} = Directive.apply_directives(agent, result)

    # Multiple directives
    directives = [
      %RegisterActionDirective{action_module: MyApp.Actions.Move},
      %EnqueueDirective{action: :move, params: %{location: :kitchen}}
    ]

    result = %Result{directives: directives}
    {:ok, updated_agent} = Directive.apply_directives(agent, result)
    ```

    ## Validation

    Each directive type has its own validation rules:

    * `EnqueueDirective` requires a non-nil atom for the action
    * `RegisterActionDirective` requires a valid module atom
    * `DeregisterActionDirective` requires a valid module atom

    Failed validation results in an error tuple being returned and processing being halted.

    ## Error Handling

    The module uses tagged tuples for error handling:

    * `{:ok, updated_agent}` - Successful application of directives
    * `{:error, reason}` - Failed validation or application

    Common error reasons include:

    * `:invalid_action` - The action specified in an `EnqueueDirective` is invalid
    * `:invalid_action_module` - The module specified in a `Register/DeregisterDirective` is invalid
  """
  use ExDbug, enabled: false
  use TypedStruct
  alias Jido.Agent
  alias Jido.Runner.Result
  alias Jido.Instruction

  typedstruct module: EnqueueDirective do
    @typedoc "Directive to enqueue a new instruction"
    field(:action, atom(), enforce: true)
    field(:params, map(), default: %{})
    field(:context, map(), default: %{})
    field(:opts, keyword(), default: [])
  end

  typedstruct module: RegisterActionDirective do
    @typedoc "Directive to register a new action module"
    field(:action_module, module(), enforce: true)
  end

  typedstruct module: DeregisterActionDirective do
    @typedoc "Directive to deregister an existing action module"
    field(:action_module, module(), enforce: true)
  end

  @type t :: EnqueueDirective.t() | RegisterActionDirective.t() | DeregisterActionDirective.t()
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

  def is_directive?(directive) when is_struct(directive, EnqueueDirective), do: true
  def is_directive?(directive) when is_struct(directive, RegisterActionDirective), do: true
  def is_directive?(directive) when is_struct(directive, DeregisterActionDirective), do: true
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

      {:ok, updated_agent} = Directive.apply_directives(agent, result)

  ## Behavior
  - Applies directives in order, stopping on first error
  - Maintains atomicity - all directives succeed or none are applied
  - Logs debug info about directive application
  """
  def apply_directives(agent, %Result{directives: directives}, opts \\ []) do
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
      case apply_directive(current_agent, directive, opts) do
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
  """
  @spec apply_directive(Agent.t(), t(), keyword()) :: directive_result()
  def apply_directive(agent, %EnqueueDirective{} = directive, _opts) do
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

  def apply_directive(agent, %RegisterActionDirective{} = directive, _opts) do
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

  def apply_directive(agent, %DeregisterActionDirective{} = directive, _opts) do
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
