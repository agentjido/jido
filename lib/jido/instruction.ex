defmodule Jido.Instruction do
  @moduledoc """
  Represents a single instruction to be executed by a Runner.  An instruction consists of an action module and optional parameters.

  Instructions are the basic unit of execution in the Jido system. They wrap an action module
  with its parameters and execution context, allowing the Runner to execute them in a
  standardized way.

  ## Fields

  - `:action` - The action module to execute (required)
  - `:params` - Map of parameters to pass to the action (default: %{})
  - `:context` - Map of execution context data (default: %{})
  - `:result` - Result of executing the instruction (default: nil)

  ## Instruction Shorthand Formats

  Instructions can be specified in several formats:

  - Action module name:
      `MyApp.Actions.DoSomething`

  - Tuple of action and params:
      `{MyApp.Actions.DoSomething, %{value: 42}}`

  - Lists of instructions:
      `[MyApp.Actions.DoSomething, {MyApp.Actions.ProcessData, %{data: "input"}}]`

  - Full instruction struct:
      ```
      %Instruction{
        action: MyApp.Actions.DoSomething,
        params: %{value: 42}
      }
      ```

  Shorthand formats are for conveinence only and will be normalized to the full instruction struct.

  ## Examples

      # Create a basic instruction
      %Instruction{
        action: MyApp.Actions.DoSomething,
        params: %{value: 42}
      }

      # With context
      %Instruction{
        action: MyApp.Actions.ProcessData,
        params: %{data: "input"},
        context: %{user_id: 123}
      }

      # Using shorthand action name
      MyApp.Actions.DoSomething

      # Using tuple shorthand
      {MyApp.Actions.ProcessData, %{data: "input"}}

  Instructions are typically created by the Agent when processing commands, and then
  executed by a Runner module like `Jido.Runner.Simple` or `Jido.Runner.Chain`.
  """
  alias Jido.Error
  use ExDbug, enabled: false
  use TypedStruct

  @type action_module :: module()
  @type action_params :: map()
  @type action_tuple :: {action_module(), action_params()}
  @type instruction :: action_module() | action_tuple() | t()
  @type instruction_list :: [instruction()]

  typedstruct do
    field(:action, module(), enforce: true)
    field(:params, map(), default: %{})
    field(:context, map(), default: %{})
    field(:opts, keyword(), default: [])
    field(:result, term(), default: nil)
  end

  @doc """
  Normalizes instruction shorthand input into instruction structs. Accepts a variety of input formats
  and returns a list of normalized instruction structs.

  ## Parameters
    * `input` - One of:
      * Single instruction struct (%Instruction{})
      * List of instruction structs
      * Single action module
      * Action tuple {module, params}
      * List of actions/tuples/instructions
    * `context` - Optional context map to merge into all instructions (default: %{})
    * `opts` - Optional keyword list of options, see `Jido.Workflow.run/4` for supported options

  ## Returns
    * `{:ok, [%Instruction{}]}` - List of normalized instruction structs
    * `{:error, term()}` - If normalization fails

  ## Examples

      iex> Instruction.normalize(MyAction)
      {:ok, [%Instruction{action: MyAction, params: %{}, context: %{}}]}

      iex> Instruction.normalize({MyAction, %{value: 1}}, %{user_id: "123"})
      {:ok, [%Instruction{action: MyAction, params: %{value: 1}, context: %{user_id: "123"}}]}

      iex> Instruction.normalize([
      ...>   %Instruction{action: MyAction, context: %{local: true}},
      ...>   {OtherAction, %{data: "test"}}
      ...> ], %{request_id: "abc"})
      {:ok, [
        %Instruction{action: MyAction, context: %{local: true, request_id: "abc"}},
        %Instruction{action: OtherAction, params: %{data: "test"}, context: %{request_id: "abc"}}
      ]}
  """
  @spec normalize(instruction() | instruction_list(), map(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def normalize(input, context \\ %{}, opts \\ [])

  # Normalize context and opts
  def normalize(input, context, opts) when not is_map(context) or not is_list(opts) do
    normalize(
      input,
      if(is_map(context), do: context, else: %{}),
      if(is_list(opts), do: opts, else: [])
    )
  end

  # Already normalized instruction
  def normalize(%__MODULE__{} = instruction, context, opts) do
    {:ok, [%{instruction | context: Map.merge(instruction.context, context), opts: opts}]}
  end

  # List containing instructions/actions
  def normalize(instructions, context, opts) when is_list(instructions) do
    dbug("Normalizing instruction list", instructions: instructions)

    instructions
    |> Enum.reduce_while({:ok, []}, fn
      # Handle existing instruction struct
      %__MODULE__{} = inst, {:ok, acc} ->
        merged = %{inst | context: Map.merge(inst.context, context), opts: opts}
        {:cont, {:ok, [merged | acc]}}

      # Handle bare action module
      action, {:ok, acc} when is_atom(action) ->
        instruction = %__MODULE__{action: action, params: %{}, context: context, opts: opts}
        {:cont, {:ok, [instruction | acc]}}

      # Handle action tuple with params
      {action, params}, {:ok, acc} when is_atom(action) ->
        case normalize_params(params) do
          {:ok, normalized_params} ->
            instruction = %__MODULE__{
              action: action,
              params: normalized_params,
              context: context,
              opts: opts
            }

            {:cont, {:ok, [instruction | acc]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end

      invalid, {:ok, _acc} ->
        dbug("Invalid instruction format", instruction: invalid)

        {:halt,
         {:error,
          Error.execution_error(
            "Invalid instruction format. Expected an instruction struct, action module, or {action, params} tuple",
            %{
              instruction: invalid,
              expected_formats: [
                "%Instruction{}",
                "MyAction",
                "{MyAction, %{param: value}}"
              ]
            }
          )}}
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  # Single action module
  def normalize(action, context, opts) when is_atom(action) do
    {:ok, [%__MODULE__{action: action, params: %{}, context: context, opts: opts}]}
  end

  # Action tuple
  def normalize({action, params}, context, opts) when is_atom(action) do
    with {:ok, normalized_params} <- normalize_params(params) do
      {:ok,
       [%__MODULE__{action: action, params: normalized_params, context: context, opts: opts}]}
    end
  end

  # Return an error for any other format
  def normalize(invalid, _context, _opts) do
    {:error, Error.execution_error("Invalid instruction format", %{instruction: invalid})}
  end

  @doc """
  Validates that all instructions use allowed actions.

  ## Parameters
    * `instructions` - List of instruction structs
    * `allowed_actions` - List of allowed action modules

  ## Returns
    * `:ok` - All actions are allowed
    * `{:error, term()}` - If any action is not allowed

  ## Examples
      iex> instructions = [%Instruction{action: MyAction}, %Instruction{action: OtherAction}]
      iex> Instruction.validate_allowed_actions(instructions, [MyAction])
      {:error, "Actions not allowed: OtherAction"}

      iex> instructions = [%Instruction{action: MyAction}]
      iex> Instruction.validate_allowed_actions(instructions, [MyAction])
      :ok
  """
  @spec validate_allowed_actions([t()], [module()]) :: :ok | {:error, term()}
  def validate_allowed_actions(instructions, allowed_actions) do
    dbug("Validating allowed actions",
      instructions: instructions,
      allowed_actions: allowed_actions
    )

    unregistered =
      instructions
      |> Enum.map(& &1.action)
      |> Enum.reject(&(&1 in allowed_actions))

    if Enum.empty?(unregistered) do
      :ok
    else
      unregistered_str = Enum.join(unregistered, ", ")

      {:error,
       Error.config_error("Actions not allowed: #{unregistered_str}", %{
         actions: unregistered,
         allowed_actions: allowed_actions
       })}
    end
  end

  # Private helpers

  defp normalize_params(nil), do: {:ok, %{}}
  defp normalize_params(params) when is_map(params), do: {:ok, params}

  defp normalize_params(invalid) do
    dbug("Invalid params format", params: invalid)

    {:error,
     Error.execution_error(
       "Invalid params format. Params must be a map.",
       %{
         params: invalid,
         expected_format: "%{key: value}"
       }
     )}
  end
end
