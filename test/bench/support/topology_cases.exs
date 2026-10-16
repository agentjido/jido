defmodule JidoCoreBench.TopologyCases do
  @moduledoc false

  alias Jido.Examples.Topology.Cell
  alias Jido.Topology
  alias Jido.Topology.{Codec, Reference}
  alias JidoCoreBench.Fixtures, as: F

  def workloads(sizes) do
    definitions =
      for base <- sizes do
        size = base * 16

        F.checked(
          "topology/definition/agents_#{size}",
          fn _context -> setup(size) end,
          fn prepared -> Topology.new(prepared) end,
          fn {:ok, definition} -> F.equal!(length(definition.agents), size) end
        )
      end

    definitions ++ planning_cases(sizes)
  end

  defp planning_cases(sizes) do
    for base <- sizes, operation <- [:plan, :encode, :decode, :decode_instance] do
      size = base * 16

      F.checked(
        "topology/composed/members_#{size}/#{operation}",
        fn _ ->
          definition = composed(size)
          {:ok, document, registry} = Codec.encode(definition)
          {:ok, instance} = Topology.instantiate(definition, id: "topology-bench")
          %{definition: definition, document: document, registry: registry, instance: instance}
        end,
        fn prepared ->
          case operation do
            :plan ->
              Topology.instantiate(prepared.definition, id: "topology-bench")

            :encode ->
              Codec.encode(prepared.definition, prepared.registry)

            :decode ->
              Codec.decode(prepared.document, prepared.registry)

            :decode_instance ->
              Codec.decode(prepared.document, prepared.registry, id: "topology-bench")
          end
        end,
        fn result -> F.equal!(elem(result, 0), :ok) end
      )
      |> Map.put(:verify, fn prepared, result ->
        expected =
          case operation do
            :encode -> prepared.document
            :decode -> prepared.definition
            _ -> prepared.instance
          end

        F.equal!(result, {:ok, expected})
        F.equal!(map_size(prepared.instance.plan.agents), size + 2)
      end)
    end
  end

  defp composed(size) do
    member = F.definition(1, JidoCoreBench.Add, [JidoCoreBench.PreparePlugin])
    leaf = %{name: "leaf", agents: [%{key: :worker, definition: member}]}

    Topology.new!(%{
      name: "composed_bench",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(size)}),
      agents: [%{key: :leader, definition: member}],
      groups: [%{key: :workers, definition: member, count: Reference.input(:count)}],
      resources: [%{key: :events}],
      relationships: [%{parent: :leader, child: :workers}],
      connections: [%{agent: :workers, to: :events, path: "bench.**"}],
      includes: [%{key: :included, topology: leaf}],
      children: [
        %{
          key: :child,
          topology: leaf,
          gate: %{commands: [%{type: "bench.run", member: :worker}]}
        }
      ]
    })
  end

  defp setup(size) do
    %{
      name: "topology_bench",
      agents: for(index <- 1..size, do: %{key: "agent-#{index}", module: Cell})
    }
  end
end
