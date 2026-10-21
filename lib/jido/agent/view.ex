defmodule Jido.Agent.View do
  @moduledoc """
  Builds a safe, framework-neutral view of one Agent.

  The view is a plain JSON document. It has the same shape for a compiled
  Agent module, a neutral data definition, and an Agent instance. The view
  includes public definition data and route summaries. It does not include
  Agent state, metadata, schema values, Plugin options, route defaults, or
  route match functions.

  The caller must supply a `Jido.Authoring.Registry`. The view uses stable
  Registry identifiers for the Agent type and included route targets. It does
  not expose modules or create identifiers from module names.

  `project/3` does not start or contact an Agent process.
  """

  alias Jido.Agent
  alias Jido.Agent.Authoring
  alias Jido.Authoring.{Document, Registry}

  @default_operation_limit 100
  @maximum_operation_limit 500

  @type json_value :: nil | boolean() | number() | String.t() | [json_value()] | projection()
  @type projection :: %{required(String.t()) => json_value()}

  @doc """
  Projects one Agent source as a JSON-safe map.

  The `:operation_limit` option is between 0 and 500. Its default is 100.
  The result reports the total operation count when the list is truncated.
  """
  @spec project(Agent.t() | module(), Registry.t() | map(), keyword()) ::
          {:ok, projection()} | {:error, term()}
  def project(source, registry, opts \\ []) do
    with {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, [:operation_limit]),
         {:ok, limit} <-
           limit(Map.get(opts, :operation_limit, @default_operation_limit)),
         {:ok, registry} <- Registry.new(registry),
         {:ok, agent} <- definition(source),
         {:ok, agent_type} <- agent_type(agent.module, registry),
         {:ok, schema} <- Registry.encode_reference(registry, :schema, agent.schema),
         {:ok, operations} <- operations(agent.routes, registry, limit),
         view <- build(agent, agent_type, schema, operations),
         :ok <- Document.check(view) do
      {:ok, view}
    end
  end

  defp agent_type(nil, _registry), do: {:ok, nil}
  defp agent_type(module, registry), do: Registry.encode_reference(registry, :agent, module)

  defp definition(%Agent{} = agent) do
    Agent.validate(agent)
  end

  defp definition(module) when is_atom(module) and not is_nil(module) do
    Jido.Agent.Validation.resolve(module)
  end

  defp definition(_source),
    do: Authoring.error("Expected an Agent definition, instance, or module")

  defp operations(routes, registry, limit) do
    total = length(routes)

    with {:ok, items} <-
           routes
           |> Enum.take(limit)
           |> Authoring.traverse(&operation(&1, registry)) do
      {:ok, %{"items" => items, "total" => total, "truncated" => total > limit}}
    end
  end

  defp operation(route, registry) do
    with {:ok, target} <- target(route.handler, registry) do
      {:ok,
       %{
         "signal_type" => route.path,
         "kind" => Atom.to_string(route.handler.kind),
         "target" => target,
         "emits" => route.emits
       }}
    end
  end

  defp target(%{kind: kind, target: target}, registry) when kind in [:action, :flow],
    do: Registry.encode_reference(registry, kind, target)

  defp target(_, _), do: {:ok, nil}

  defp build(agent, agent_type, schema, operations) do
    %{
      "type" => "jido.agent.view",
      "vsn" => 1,
      "id" => agent.id,
      "name" => agent.name,
      "description" => agent.description,
      "definition_vsn" => agent.vsn,
      "agent_type" => agent_type,
      "schema" => schema,
      "operations" => operations
    }
  end

  defp limit(value)
       when is_integer(value) and value >= 0 and value <= @maximum_operation_limit,
       do: {:ok, value}

  defp limit(_value),
    do:
      Authoring.error(
        "Agent view operation_limit must be an integer from 0 through #{@maximum_operation_limit}"
      )
end
