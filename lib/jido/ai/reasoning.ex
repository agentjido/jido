defmodule Jido.AI.Reasoning do
  @moduledoc """
  Small inspection helpers for a graph-first AI Agent.

  AI Agent modules expose these helpers through `reasoning/0`, `explain/0`,
  and `preflight/1`. They inspect and compile the root Flow without running it.
  """

  @request_type "jido.ai.request"

  @doc "Returns the root reasoning Flow module."
  @spec root(module()) :: module()
  def root(agent) when is_atom(agent) do
    agent
    |> route!()
    |> Map.fetch!(:handler)
    |> Map.fetch!(:target)
  end

  @doc "Returns the root Flow, schemas, defaults, and Agent-local tools."
  @spec explain(module()) :: map()
  def explain(agent) when is_atom(agent) do
    route = route!(agent)
    reasoning = route.handler.target

    %{
      agent: agent,
      reasoning: reasoning,
      defaults: route.defaults,
      input_schema: reasoning.schema(),
      output_schema: reasoning.output_schema(),
      tools: tools(agent),
      flow: reasoning.flow()
    }
  end

  @doc "Validates one request and compiles its root Flow without execution."
  @spec preflight(module(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def preflight(agent, input) when is_atom(agent) do
    route = route!(agent)
    reasoning = route.handler.target
    actions = tools(agent)

    with {:ok, input} <- input_map(input),
         {:ok, params} <- Jido.Agent.Route.params(route, input),
         {:ok, params} <- reasoning.validate_params(params),
         :ok <- Jido.AI.Toolset.validate(actions),
         {:ok, instruction} <- Jido.Instruction.resolve(reasoning, params, %{}),
         {:ok, workflow} <- Jido.Exec.compile(instruction) do
      {:ok,
       %{
         agent: agent,
         reasoning: reasoning,
         params: params,
         tools: actions,
         flow: reasoning.flow(),
         workflow: workflow
       }}
    end
  rescue
    error -> {:error, error}
  end

  defp route!(agent) do
    case Enum.find(agent.definition().routes, &(&1.path == @request_type)) do
      %{handler: %{kind: :flow, target: target}} = route when is_atom(target) ->
        route

      _route ->
        raise ArgumentError,
              "#{inspect(agent)} does not define one jido.ai.request reasoning Flow"
    end
  end

  defp tools(agent) do
    agent.definition().plugins
    |> Enum.find_value([], fn
      %{provider: Jido.AI.Agent.Plugin, data: %{tools: actions}} -> actions
      _plugin -> nil
    end)
  end

  defp input_map(input) when is_map(input) and not is_struct(input), do: {:ok, input}

  defp input_map(input) when is_list(input) do
    if Keyword.keyword?(input), do: {:ok, Map.new(input)}, else: {:error, :invalid_input}
  end

  defp input_map(_input), do: {:error, :invalid_input}
end
