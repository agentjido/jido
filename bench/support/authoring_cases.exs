defmodule JidoCoreBench.AuthoringCases do
  @moduledoc false
  alias Jido.Agent.{Builder, Codec}
  alias Jido.Agent.Codec.Deriver
  alias JidoCoreBench.Fixtures, as: F

  def workloads(sizes), do: builder_cases(sizes) ++ registry_cases()

  defp builder_cases(sizes) do
    for size <- sizes, mode <- [:bulk, :incremental, :mixed] do
      F.checked(
        "authoring/builder/#{size}/#{mode}",
        fn _ -> F.definition(size) end,
        fn definition ->
          attrs = definition |> Jido.Agent.to_map() |> Map.drop([:id, :state, :routes])
          routes = definition.routes

          {initial, appended} =
            case mode do
              :bulk -> {routes, []}
              :incremental -> {[], routes}
              :mixed -> Enum.split(routes, div(size, 2))
            end

          Enum.reduce(appended, Builder.new(Map.put(attrs, :routes, initial)), fn route,
                                                                                  builder ->
            Builder.route(builder, route.path, route.target,
              priority: route.priority,
              match: route.match
            )
          end)
          |> Builder.build()
        end,
        fn {:ok, definition} -> F.equal!(length(definition.routes), size) end
      )
      |> Map.put(:verify, fn definition, result -> F.equal!(result, {:ok, definition}) end)
    end
  end

  defp registry_cases do
    for size <- [1, 256], shape <- [:flat, :nested], operation <- [:derive, :encode] do
      F.checked(
        "authoring/registry/#{size}/#{shape}/#{operation}",
        fn _ ->
          values = for n <- 1..size, do: %URI{host: "host-#{n}", port: n}

          data =
            if shape == :nested, do: Enum.map(values, &%{value: {:item, [&1, &1]}}), else: values

          definition = %{F.definition() | metadata: %{items: data}}
          {:ok, document, registry} = Codec.encode(definition)
          {definition, document, registry}
        end,
        fn {definition, _document, _registry} ->
          case operation do
            :derive -> Deriver.agent(definition)
            :encode -> Codec.encode(definition)
          end
        end,
        fn result -> F.equal!(elem(result, 0), :ok) end
      )
      |> Map.put(:verify, fn {definition, document, registry}, result ->
        case operation do
          :derive ->
            F.equal!(result, {:ok, registry})

          :encode ->
            F.equal!(result, {:ok, document, registry})
            F.equal!(Codec.decode(document, registry), {:ok, definition})
        end
      end)
    end
  end
end
