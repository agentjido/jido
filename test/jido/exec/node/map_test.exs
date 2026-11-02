defmodule Jido.Exec.Node.MapTest do
  use Covenant.Case, component: "jido_action.boundary", async: true

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.Actions.EchoParamsAction

  defmodule FallibleAction do
    use Jido.Action, name: "exec_v2_fallible_map"

    @impl true
    def run(%{value: :bad}, _context), do: {:error, :bad_item}
    def run(%{value: value}, _context), do: {:ok, %{value: value}}
  end

  defmodule RetryAction do
    use Jido.Action, name: "batch_retry"

    @impl true
    def run(%{index: index} = params, %{counter: counter}) do
      attempt =
        Agent.get_and_update(counter, fn counts ->
          attempt = Map.get(counts, index, 0) + 1
          {attempt, Map.put(counts, index, attempt)}
        end)

      if index == 1 and attempt == 1,
        do: {:error, Jido.Action.Error.execution_error("retry item", %{retry: true})},
        else: {:ok, params, [index]}
    end
  end

  defmodule LocalOutput do
    use Jido.Action, name: "batch_local_output"

    @impl true
    def run(_params, _context), do: {:ok, %{owner: self(), reference: make_ref()}}
  end

  defmodule MapChild do
    use Jido.Flow, name: "batch_child"

    flow do
      map "items", collection: input(:items), action: EchoParamsAction, params: %{id: item_id()}
      output %{items: result("items")}
    end
  end

  @tag obligation: "jido_action.boundary.I7"
  test "Map uses native Batch and keeps input order" do
    flow = map_flow(EchoParamsAction, %{index: Ref.item_index(), value: Ref.item()}, :fail_fast)

    rebuilt = flow |> Exec.compile!() |> Runic.Workflow.build_log() |> Runic.Workflow.from_log()
    assert %Jido.Exec.Node.Map{} = Runic.Workflow.get_component(rebuilt, "items")

    assert %Runic.Workflow.Batch{} =
             Runic.Workflow.get_component(rebuilt, "__jido_map__/items/batch")

    assert Enum.any?(rebuilt.graph.vertices, fn {_id, node} ->
             match?(%Runic.Workflow.FanOut{}, node)
           end)

    assert Enum.any?(rebuilt.graph.vertices, fn {_id, node} ->
             match?(%Runic.Workflow.FanIn{}, node)
           end)

    assert Exec.run(flow, %{items: [3, 1, 2]}) ==
             {:ok,
              %{
                items: [
                  %{index: 0, value: 3},
                  %{index: 1, value: 1},
                  %{index: 2, value: 2}
                ]
              }}

    assert Exec.run(flow, %{items: []}) == {:ok, %{items: []}}
  end

  @tag obligation: "jido_action.boundary.I7"
  test "an empty native batch has no item invocation" do
    flow = map_flow(EchoParamsAction, %{value: Ref.item()}, :fail_fast)
    definition = Exec.compile!(flow)
    batch = Runic.Workflow.get_component(definition, "__jido_map__/items/batch")
    assert %Runic.Workflow.Batch{} = batch

    {workflow, observation} =
      Runic.Workflow.execute(definition, Jido.Exec.Frame.new(%{items: []}))

    assert Exec.result(workflow, observation) == {:ok, %{items: []}}
    assert [id] = Runic.Workflow.Batch.invocations(workflow, batch)
    assert {:ok, []} = Runic.Workflow.Batch.outcomes(workflow, batch, id)
    assert Runic.Workflow.raw_productions(workflow, batch.component.name) == []
  end

  @tag obligation: "jido_action.boundary.I7"
  test "shared parent data stays outside native item Facts" do
    flow = map_flow(EchoParamsAction, %{value: Ref.item()}, :fail_fast)
    input = %{items: [2, 2, 1], padding: Enum.to_list(1..1_000)}
    definition = Exec.compile!(flow)
    batch = Runic.Workflow.get_component(definition, "__jido_map__/items/batch")
    assert %Runic.Workflow.Batch{} = batch
    {workflow, observation} = Runic.Workflow.execute(definition, Jido.Exec.Frame.new(input))

    assert Exec.result(workflow, observation) ==
             {:ok, %{items: [%{value: 2}, %{value: 2}, %{value: 1}]}}

    items =
      workflow
      |> Runic.Workflow.facts()
      |> Enum.filter(&match?(%{ancestry: {producer, _}} when producer == batch.fan_out.hash, &1))

    assert length(items) == 3
    assert Enum.all?(items, &match?({:jido_map_item, _, _, _}, &1.value))
    assert Enum.all?(items, &(:erlang.external_size(&1.value) < 256))

    for item <- items do
      assert {:ok, runnable} = Runic.Workflow.Invokable.prepare(batch.component, workflow, item)
      refute Map.has_key?(runnable.context.batch, :parent)
      assert runnable.context.batch.item_id == item.hash
    end
  end

  @tag obligation: "jido_action.boundary.I7"
  test "native batches preserve local item values" do
    flow = map_flow(EchoParamsAction, %{value: Ref.item()}, :fail_fast)
    item = %{owner: self(), reference: make_ref(), uri: URI.parse("/batch")}

    assert Exec.run(flow, %{items: [item, item]}, %{}, max_concurrency: 2) ==
             {:ok, %{items: [%{value: item}, %{value: item}]}}
  end

  @tag obligation: "jido_action.boundary.I7"
  test "a completed batch preserves local execution for a following Action" do
    flow =
      Flow.new!(%{
        name: "batch_then_local",
        components: [
          %{
            kind: :map,
            name: "items",
            collection: Ref.input(:items),
            action: EchoParamsAction,
            params: %{value: Ref.item()}
          },
          %{kind: :step, name: "local", action: LocalOutput, needs: ["items"]}
        ],
        output: Ref.result("local")
      })

    for items <- [[], [1]] do
      assert {:ok, %{owner: owner, reference: reference}} = Exec.run(flow, %{items: items})
      assert is_pid(owner)
      assert is_reference(reference)
    end
  end

  @tag obligation: "jido_action.boundary.I7"
  test "repeated native executions have separate batches and keep public item IDs" do
    flow = map_flow(EchoParamsAction, %{id: Ref.item_id(), value: Ref.item()}, :fail_fast)
    definition = Exec.compile!(flow)
    batch = Runic.Workflow.get_component(definition, "__jido_map__/items/batch")

    {outputs, workflow} =
      Enum.map_reduce([[], [2, 2], [2, 2]], definition, fn items, workflow ->
        {workflow, observation} =
          Runic.Workflow.execute(workflow, Jido.Exec.Frame.new(%{items: items}))

        assert {:ok, output} = Exec.result(workflow, observation)
        {output, workflow}
      end)

    assert [%{items: []}, %{items: [first, second]} = repeated, repeated] = outputs
    assert first.value == second.value
    assert first.id != second.id
    ids = Runic.Workflow.Batch.invocations(workflow, batch)
    assert length(ids) == 3
    assert length(Enum.uniq(ids)) == 3
  end

  @tag obligation: "jido_action.boundary.I7"
  test "nested Map exports rebuild with separate native batches" do
    flow =
      Flow.new!(%{
        name: "nested_batches",
        components:
          for name <- ["left", "right"] do
            %{
              kind: :subflow,
              name: name,
              flow: MapChild,
              params: %{items: Ref.input(:items)}
            }
          end,
        output: %{left: Ref.result("left"), right: Ref.result("right")}
      })

    assert {:ok, %{left: %{items: [%{id: left}]}, right: %{items: [%{id: right}]}} = expected} =
             Exec.run(flow, %{items: [1]})

    assert left != right
    rebuilt = flow |> Exec.compile!() |> Runic.Workflow.build_log() |> Runic.Workflow.from_log()

    {workflow, observation} =
      Runic.Workflow.execute(rebuilt, Jido.Exec.Frame.new(%{items: [1]}))

    assert Exec.result(workflow, observation) == {:ok, expected}
  end

  @tag :capture_log
  @tag obligation: "jido_action.boundary.I7"
  test "native batches retry fail-fast items but keep collected errors as data" do
    for mode <- [:fail_fast, :collect_errors] do
      counter = start_supervised!({Agent, fn -> %{} end}, id: mode)
      flow = map_flow(RetryAction, %{index: Ref.item_index(), value: Ref.item()}, mode)

      assert {:ok, %{items: items}, effects} =
               Exec.run(flow, %{items: [4, 4, 2]}, %{counter: counter},
                 max_attempts: 2,
                 max_concurrency: 3
               )

      if mode == :fail_fast do
        assert items == [%{index: 0, value: 4}, %{index: 1, value: 4}, %{index: 2, value: 2}]
        assert effects == [0, 1, 2]
        assert Agent.get(counter, & &1) == %{0 => 1, 1 => 2, 2 => 1}
      else
        assert Enum.map(items, & &1.status) == [:ok, :error, :ok]
        assert effects == [0, 2]
        assert Agent.get(counter, & &1) == %{0 => 1, 1 => 1, 2 => 1}
      end
    end
  end

  @tag obligation: "jido_action.boundary.I7"
  test "a failed Map Action retains its source item position" do
    flow = map_flow(FallibleAction, %{value: Ref.item()}, :fail_fast)
    assert {:error, error} = Exec.run(flow, %{items: [:a, :bad, :c]})
    assert error.details.node == "items"
    assert error.details.item_index == 1
    assert is_binary(error.details.item_id)
  end

  @tag obligation: "jido_action.boundary.I7"
  test "Map can collect Action errors as ordered data" do
    flow = map_flow(FallibleAction, %{value: Ref.item()}, :collect_errors)

    assert {:ok, %{items: [first, failed, third]}} = Exec.run(flow, %{items: [:a, :bad, :c]})
    assert first == %{status: :ok, value: %{value: :a}}

    assert %{
             status: :error,
             error: %{
               type: :execution_error,
               message: "bad_item",
               retryable?: false,
               details: details
             }
           } = failed

    assert %{node: "items", target: FallibleAction, item_index: 1, item_id: item_id} = details
    assert is_binary(item_id)
    refute Map.has_key?(details, :stacktrace)
    assert third == %{status: :ok, value: %{value: :c}}
  end

  @tag obligation: "jido_action.boundary.I7"
  test "Map collects parameter reference failures without item identity" do
    flow = map_flow(EchoParamsAction, %{value: Ref.item(:value)}, :collect_errors)

    assert {:ok, %{items: [first, failed, third]}} =
             Exec.run(flow, %{items: [%{value: 1}, %{}, %{value: 3}]})

    assert first == %{status: :ok, value: %{value: 1}}
    assert third == %{status: :ok, value: %{value: 3}}

    assert %{status: :error, error: %{type: :flow_execution_error, details: details}} = failed
    assert %{reason: :missing_key, path: [:value], ref_type: :item} = details
    refute Map.has_key?(details, :item_id)
    refute Map.has_key?(details, :item_index)
    refute Map.has_key?(details, :target)
  end

  @tag obligation: "jido_action.boundary.I7"
  test "Map handles a large collection read from Flow input" do
    flow = map_flow(EchoParamsAction, %{value: Ref.item()}, :fail_fast)
    items = Enum.to_list(1..1_000)

    assert {:ok, %{items: results}} = Exec.run(flow, %{items: items})
    assert Enum.map(results, & &1.value) == items
  end

  @tag obligation: "jido_action.boundary.I7"
  test "Map item IDs follow the Flow, component name, and source index" do
    flow =
      Flow.new!(%{
        name: "map_ids",
        components:
          for name <- ["left", "right"] do
            %{
              kind: :map,
              name: name,
              collection: Ref.input(:items),
              action: EchoParamsAction,
              params: %{id: Ref.item_id()}
            }
          end,
        output: %{left: Ref.result("left"), right: Ref.result("right")}
      })

    assert {:ok, %{left: [%{id: left}], right: [%{id: right}]}} = Exec.run(flow, %{items: [1]})
    assert left != right
    assert {:ok, %{left: [%{id: ^left}]}} = Exec.run(flow, %{items: [2]})
  end

  defp map_flow(action, params, on_error) do
    Flow.new!(%{
      name: "map",
      components: [
        %{
          kind: :map,
          name: "items",
          collection: Ref.input(:items),
          action: action,
          params: params,
          on_error: on_error
        }
      ],
      output: %{items: Ref.result("items")}
    })
  end
end
