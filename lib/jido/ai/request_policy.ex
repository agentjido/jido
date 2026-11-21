defmodule Jido.AI.RequestPolicy do
  @moduledoc """
  Keeps Agent-level AI policy in force for one request.

  A request can narrow the policy that an Agent sets on its reasoning Flow, but
  it cannot widen or remove that policy:

    * `instructions` set on the Agent stay. A request cannot replace them.
    * `review_tools: true` set on the Agent stays.
    * `tool_policy` combines with the Agent's policy through
      `Jido.AI.Toolset.narrow_policy/2`.
    * Each limit set on the Agent is an upper bound. A limit that the request
      leaves out keeps the Agent's value, and `nil` cannot remove it.

  Fields that the Agent does not set follow the request as usual.
  """

  alias Jido.AI.Agent.Plugin
  alias Jido.AI.Toolset
  alias Jido.Joi

  @policy_fields [:instructions, :review_tools, :tool_policy, :limits]
  @neutral_tool_policy %{visible: [], hidden: [], review: [], requirement: :optional, reason: nil}

  @limit_params %{
    model_calls: :max_model_calls,
    tool_rounds: :max_tool_rounds,
    tool_calls: :max_tool_calls,
    retries: :max_retries,
    elapsed_ms: :max_elapsed_ms,
    input_tokens: :max_input_tokens,
    output_tokens: :max_output_tokens,
    total_tokens: :max_total_tokens,
    total_cost: :max_total_cost,
    tool_output_bytes: :max_tool_output_bytes,
    output_chars: :max_output_chars
  }

  @doc false
  @spec prepare(module(), map(), map(), map()) :: map()
  def prepare(flow, params, defaults, request) do
    case Map.take(defaults, @policy_fields) do
      policy when map_size(policy) == 0 -> params
      policy -> apply_policy(flow.schema(), params, policy, request)
    end
  end

  defp apply_policy(schema, params, policy, request) do
    fields =
      case Joi.Schema.fields(schema) do
        {:ok, fields} when is_list(fields) -> fields
        _other -> []
      end

    # Leave invalid input for normal Flow validation, even when policy could replace it.
    policy = Map.reject(policy, fn {key, _value} -> invalid_policy_field?(fields, request, key) end)
    effective = narrow(params, policy, request)

    with %{tool_policy: _agent_policy} <- policy,
         {:ok, schema} <- Keyword.fetch(fields, :tool_policy),
         {:ok, policy_fields} when is_list(policy_fields) <- Joi.Schema.fields(schema) do
      # A custom Flow can omit standard fields when they have no policy effect.
      Map.update!(effective, :tool_policy, fn tool_policy ->
        Map.reject(tool_policy, fn {key, value} ->
          not Keyword.has_key?(policy_fields, key) and Map.fetch!(@neutral_tool_policy, key) == value
        end)
      end)
    else
      _other -> effective
    end
  end

  defp invalid_policy_field?(fields, request, key) do
    with {:ok, schema} <- Keyword.fetch(fields, key),
         {:ok, value} <- Map.fetch(request, key) do
      not match?({:ok, _value}, Joi.parse(schema, value))
    else
      _other -> false
    end
  end

  @doc "Applies Agent defaults to validated Flow input, given the raw request data."
  @spec narrow(map(), map(), map()) :: map()
  def narrow(params, defaults, request) when is_map(params) and is_map(defaults) and is_map(request) do
    params
    |> keep_instructions(defaults)
    |> keep_review(defaults)
    |> narrow_tool_policy(defaults)
    |> narrow_limits(defaults, request)
  end

  @doc "Applies the current Agent's defaults to the flat parameters of a request start."
  @spec narrow_start(map(), map()) :: map()
  def narrow_start(params, context) when is_map(params) and is_map(context) do
    limits =
      for {limit, param} <- @limit_params, is_map_key(params, param), into: %{} do
        {limit, Map.fetch!(params, param)}
      end

    narrowed =
      params
      |> Map.put(:limits, limits)
      |> narrow(Plugin.prepared_defaults(context), request(context))

    @limit_params
    |> Enum.filter(fn {_limit, param} -> is_map_key(params, param) end)
    |> Enum.reduce(Map.delete(narrowed, :limits), fn {limit, param}, result ->
      Map.put(result, param, Map.fetch!(narrowed.limits, limit))
    end)
  end

  defp keep_instructions(params, %{instructions: instructions}),
    do: Map.put(params, :instructions, instructions)

  defp keep_instructions(params, _defaults), do: params

  defp keep_review(params, %{review_tools: true}), do: Map.put(params, :review_tools, true)
  defp keep_review(params, _defaults), do: params

  defp narrow_tool_policy(params, %{tool_policy: agent_policy}) do
    Map.put(params, :tool_policy, Toolset.narrow_policy(agent_policy, map_field(params, :tool_policy)))
  end

  defp narrow_tool_policy(params, _defaults), do: params

  defp narrow_limits(params, %{limits: agent_limits}, request) when is_map(agent_limits) do
    limits = map_field(params, :limits)
    requested = map_field(request, :limits)

    narrowed =
      Enum.reduce(agent_limits, limits, fn {key, agent_value}, result ->
        value = if is_map_key(requested, key), do: tighter(agent_value, Map.get(limits, key)), else: agent_value
        Map.put(result, key, value)
      end)

    Map.put(params, :limits, narrowed)
  end

  defp narrow_limits(params, _defaults, _request), do: params

  defp map_field(map, key) do
    case Map.get(map, key) do
      value when is_map(value) -> value
      _other -> %{}
    end
  end

  defp tighter(nil, value), do: value
  defp tighter(agent_value, nil), do: agent_value
  defp tighter(agent_value, value), do: min(agent_value, value)

  defp request(%{signal: %{data: data}}) do
    case Jido.Agent.Validation.normalize_input(data) do
      {:ok, request} -> request
      {:error, _reason} -> %{}
    end
  end

  defp request(_context), do: %{}
end
