defmodule Jido.Flow.Authoring.GeneratedGraphTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  @moduletag :authoring
  alias Jido.{Exec, Flow}
  alias Jido.Flow.{Codec, Ref}
  alias Jido.Test.Flow.Codec, as: Codec
  alias Jido.Test.Flow.Component, as: FlowComponent

  defmodule Add do
    use Jido.Action, name: "generated_graph_add"
    @impl true
    def run(%{id: id, left: left, right: right, delta: delta}, %{
          observer: observer,
          run_ref: run_ref
        }) do
      send(observer, {:generated_graph_step, run_ref, id, left, right})
      {:ok, %{value: left + right + delta}}
    end
  end

  property("small DAGs keep results and dependency order across authoring forms") do
    check(all(graph <- graph_generator(1), max_runs: 80)) do
      flow = build_flow(graph.nodes)
      output = output(graph.nodes)

      data =
        Map.put(
          graph.nodes
          |> Enum.reverse()
          |> Enum.reduce(%{components: [], name: flow.name}, fn node, data ->
            Map.update!(
              data,
              :components,
              &(&1 ++
                  [
                    %{
                      kind: :step,
                      name: node.name,
                      action: Add,
                      params: params(node),
                      needs: node.needs
                    }
                  ])
            )
          end),
          :output,
          output
        )

      assert {:ok, built} = Jido.Test.Flow.Builder.new(data)
      assert {:ok, document, registry} = Codec.encode(flow)
      json = JSON.encode!(document)
      assert {:ok, restored} = Codec.decode(JSON.decode!(json), registry)
      assert {:ok, reencoded} = Codec.encode(restored, registry)
      assert JSON.encode!(reencoded) == json
      assert built == flow
      assert restored == flow
      assert {:ok, dependencies} = Flow.dependencies(flow)

      for node <- graph.nodes do
        parents = referenced_parents(node)
        assert dependencies[node.name].references == parents
        assert dependencies[node.name].needs == node.needs
        assert dependencies[node.name].effective == Enum.sort(Enum.uniq(parents ++ node.needs))
      end

      expected = model(graph)

      for authored <- [flow, built, restored] do
        run_ref = make_ref()

        assert Exec.run(authored, %{seed: graph.seed}, %{observer: self(), run_ref: run_ref}, max_concurrency: 4) ==
                 {:ok, expected}

        events =
          for _ <- graph.nodes do
            assert_receive {:generated_graph_step, ^run_ref, id, left, right}, 1000
            {id, left, right}
          end

        assert Enum.sort(Enum.map(events, &elem(&1, 0))) == Enum.sort(Map.keys(expected))

        positions =
          events
          |> Enum.with_index()
          |> Map.new(fn {{id, _left, _right}, index} -> {id, index} end)

        for node <- graph.nodes do
          expected_left = input_value(node.left_parent, graph.seed, expected)
          expected_right = input_value(node.right_parent, graph.seed, expected)
          assert {node.name, expected_left, expected_right} in events

          for prerequisite <- Enum.uniq(referenced_parents(node) ++ node.needs) do
            assert Map.fetch!(positions, prerequisite) < Map.fetch!(positions, node.name)
          end
        end

        refute_received {:generated_graph_step, ^run_ref, _, _, _}
      end
    end
  end

  property("generated duplicate, unknown, and cyclic graphs reject in every data form") do
    check(
      all(
        graph <- graph_generator(2),
        fault <- member_of([:duplicate, :unknown_need, :cycle]),
        max_runs: 80
      )
    ) do
      valid = build_flow(graph.nodes)
      assert {:ok, document, registry} = Codec.encode(valid)
      components = invalid_components(FlowComponent.to_definition(valid.components), fault)
      expected_message = expected_error(fault)

      assert {:error, %{message: ^expected_message}} =
               Jido.Test.Flow.Builder.new(
                 name: valid.name,
                 components: components,
                 output: valid.output
               )

      data = %{output: valid.output, components: components, name: valid.name}

      assert {:error, %{message: ^expected_message}} = Jido.Test.Flow.Builder.new(data)
      invalid_json = document |> invalid_document(fault) |> JSON.encode!() |> JSON.decode!()
      assert {:error, %{message: ^expected_message}} = Codec.decode(invalid_json, registry)
      run_ref = make_ref()

      assert {:error, _error} =
               Exec.run(%{valid | components: components}, %{seed: graph.seed}, %{
                 observer: self(),
                 run_ref: run_ref
               })

      refute_received {:generated_graph_step, ^run_ref, _, _, _}
    end
  end

  defp graph_generator(min_nodes) do
    bind(integer(min_nodes..7), fn count ->
      nodes =
        for index <- 1..count do
          node_generator(index)
        end

      bind(fixed_list(nodes), fn generated_nodes ->
        map(integer(-20..20), &%{seed: &1, nodes: generated_nodes})
      end)
    end)
  end

  defp node_generator(index) do
    needs =
      if index == 1 do
        constant([])
      else
        integer(1..(index - 1))
        |> list_of(max_length: min(index - 1, 3))
        |> map(fn indexes -> indexes |> Enum.uniq() |> Enum.map(&name/1) end)
      end

    fixed_list([integer(0..(index - 1)), integer(0..(index - 1)), needs, integer(-5..5)])
    |> map(fn [left_parent, right_parent, needs, delta] ->
      %{
        name: name(index),
        left_parent: left_parent,
        right_parent: right_parent,
        needs: needs,
        delta: delta
      }
    end)
  end

  defp name(index) do
    "node_#{index}"
  end

  defp params(node) do
    left =
      if node.left_parent == 0 do
        Ref.input(:seed)
      else
        Ref.result(name(node.left_parent), :value)
      end

    right =
      if node.right_parent == 0 do
        Ref.input(:seed)
      else
        Ref.result(name(node.right_parent), :value)
      end

    %{id: node.name, left: left, right: right, delta: node.delta}
  end

  defp referenced_parents(node) do
    [node.left_parent, node.right_parent]
    |> Enum.reject(&(&1 == 0))
    |> Enum.map(&name/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp output(nodes) do
    Map.new(nodes, fn node -> {node.name, Ref.result(node.name, :value)} end)
  end

  defp build_flow(nodes) do
    Jido.Test.Flow.Builder.new!(
      name: "generated_graph",
      components:
        nodes
        |> Enum.reverse()
        |> Enum.map(fn node ->
          Jido.Test.Flow.Component.step!(
            name: node.name,
            action: Add,
            params: params(node),
            needs: node.needs
          )
        end),
      output: output(nodes)
    )
  end

  defp model(%{nodes: nodes, seed: seed}) do
    Enum.reduce(nodes, %{}, fn node, values ->
      left = input_value(node.left_parent, seed, values)
      right = input_value(node.right_parent, seed, values)
      Map.put(values, node.name, left + right + node.delta)
    end)
  end

  defp input_value(0, seed, _values) do
    seed
  end

  defp input_value(parent, _seed, values) do
    Map.fetch!(values, name(parent))
  end

  defp invalid_components(components, :duplicate) do
    first_name = hd(components).name
    List.update_at(components, 1, &%{&1 | name: first_name})
  end

  defp invalid_components(components, :unknown_need) do
    List.update_at(components, 0, &%{&1 | needs: ["absent"]})
  end

  defp invalid_components(components, :cycle) do
    first_name = Enum.at(components, 0).name
    second_name = Enum.at(components, 1).name

    components
    |> List.update_at(0, &%{&1 | needs: [second_name]})
    |> List.update_at(1, &%{&1 | needs: [first_name]})
  end

  defp invalid_document(document, :duplicate) do
    put_in(
      document,
      ["components", Access.at(1), "name"],
      get_in(document, ["components", Access.at(0), "name"])
    )
  end

  defp invalid_document(document, :unknown_need) do
    put_in(document, ["components", Access.at(0), "needs"], ["absent"])
  end

  defp invalid_document(document, :cycle) do
    first_name = get_in(document, ["components", Access.at(0), "name"])
    second_name = get_in(document, ["components", Access.at(1), "name"])

    document
    |> put_in(["components", Access.at(0), "needs"], [second_name])
    |> put_in(["components", Access.at(1), "needs"], [first_name])
  end

  defp expected_error(:duplicate) do
    "duplicate component name"
  end

  defp expected_error(:unknown_need) do
    "Flow reference points to an unknown component"
  end

  defp expected_error(:cycle) do
    "flow dependency graph contains a cycle"
  end
end
