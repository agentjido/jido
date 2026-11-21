defmodule Jido.BehaviorTree.Nodes.Action do
  @moduledoc """
  A leaf node that executes a Jido Action.

  The Action node wraps a Jido Action module and executes it when ticked.
  The action result is converted to behavior tree statuses:
  - `{:ok, result}` -> `:success`
  - `{:error, reason}` -> `{:error, reason}`

  Parameters can read values from the blackboard. On success, the node stores
  the output in its result and in the blackboard under `:last_result`. In an
  Agent tick, a plain map result also updates candidate Agent state. Directives
  stay in the Tick for the caller to handle.

  ## Example

      action = Action.new(MyApp.Actions.SendEmail, %{
        to: "user@example.com",
        subject: "Hello"
      })

  ## Using Blackboard Values

  You can reference blackboard values using the `:from_blackboard` option:

      action = Action.new(MyApp.Actions.ProcessData, %{
        data: {:from_blackboard, :input_data}
      })

  """

  alias Jido.BehaviorTree.{Error, Expression, Tick}

  @schema Zoi.struct(
            __MODULE__,
            %{
              action_module: Zoi.any(description: "The Jido Action module to execute"),
              params: Zoi.any(description: "Parameters to pass to the action") |> Zoi.default(%{}),
              context: Zoi.any(description: "Context to pass to the action") |> Zoi.default(%{}),
              result: Zoi.any(description: "The result of the last execution") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for this module"
  def schema, do: @schema

  @behaviour Jido.BehaviorTree.Node

  @doc """
  Creates a new Action node for the given action module.

  ## Parameters

  - `action_module` - The Jido Action module to execute
  - `params` - Parameters to pass to the action (default: %{})
  - `context` - Context to pass to the action (default: %{})

  ## Examples

      iex> Action.new(MyAction)
      %Action{action_module: MyAction, params: %{}, context: %{}}

      iex> Action.new(MyAction, %{input: "value"})
      %Action{action_module: MyAction, params: %{input: "value"}, context: %{}}

  """
  @spec new(module(), map() | Expression.t(), map()) :: t()
  def new(action_module, params \\ %{}, context \\ %{}) do
    %__MODULE__{
      action_module: action_module,
      params: params,
      context: context,
      result: nil
    }
  end

  @impl true
  def tick(state, tick) do
    {status, state, _tick} = tick_with_context(state, tick)
    {status, state}
  end

  @impl true
  def tick_with_context(%__MODULE__{} = node, tick) do
    context = Map.merge(node.context, tick.context)
    state = agent_state(tick)
    context = if state, do: Map.merge(context, %{agent_state: state, state: state}), else: context

    with {:ok, params} <- resolve_params(node.params, tick) do
      Jido.Exec.run(node.action_module, params, context)
    end
    |> finish(node, tick, state)
  end

  defp finish(result, node, tick, state) do
    case result do
      {:ok, result} ->
        success(node, tick, state, result, [])

      {:ok, result, directives} ->
        success(node, tick, state, result, directives)

      {:error, reason} ->
        {{:error, reason}, node, Tick.put(tick, :error, reason)}
    end
  end

  defp agent_state(%Tick{agent: %Jido.Agent{state: state}}), do: state
  defp agent_state(%Tick{context: context}), do: Map.get(context, :agent_state)

  defp success(node, tick, state, result, directives) do
    tick =
      tick
      |> merge_state(state, result)
      |> Tick.append_directives(directives)
      |> Tick.put(:last_result, result)

    {:success, %{node | result: result}, tick}
  end

  defp merge_state(tick, state, result)
       when is_map(state) and is_map(result) and not is_struct(result) do
    state = Map.merge(state, result)

    case tick do
      %Tick{agent: %Jido.Agent{} = agent} -> Tick.update_agent(tick, %{agent | state: state})
      %Tick{} -> %{tick | context: Map.put(tick.context, :agent_state, state)}
    end
  end

  defp merge_state(tick, _state, _result), do: tick

  @impl true
  def halt(state) do
    %{state | result: nil}
  end

  defp resolve_params(%Expression{} = expression, tick) do
    case Expression.evaluate(expression, tick) do
      {:ok, params} when is_map(params) and not is_struct(params) -> {:ok, params}
      {:ok, _} -> {:error, Error.execution_error("Action params must evaluate to a map")}
      {:error, _} = error -> error
    end
  end

  defp resolve_params(params, tick) do
    {:ok, Map.new(params, fn {key, value} -> {key, resolve_value(value, tick)} end)}
  end

  defp resolve_value({:from_blackboard, key}, tick) do
    Tick.get(tick, key)
  end

  defp resolve_value(value, _tick) do
    value
  end
end
