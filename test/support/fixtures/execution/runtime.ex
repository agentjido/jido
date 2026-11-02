defmodule JidoActionTest.Fixtures.Execution do
  @moduledoc false

  alias Jido.{Exec, Instruction}
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.ConcurrencyProbeAction

  alias JidoActionTest.Fixtures.Actions.{
    Add,
    EchoParamsAction,
    MapProbeAction,
    Multiply,
    ReduceProbeAction
  }

  defmodule BlockingAction do
    @moduledoc false
    use Jido.Action, name: "blocking_action"

    def run(params, %{test_pid: test_pid}) do
      send(test_pid, {:blocking_flow_node_started, self()})

      receive do
        :finish -> {:ok, params}
      end
    end
  end

  def linear_flow do
    JidoActionTest.FlowBuilder.new!(
      name: "step_linear",
      components: [
        JidoActionTest.FlowComponent.step!(
          name: :add,
          action: Add,
          params: %{value: Ref.input(:value), amount: 1}
        ),
        JidoActionTest.FlowComponent.step!(
          name: :multiply,
          action: Multiply,
          params: %{value: Ref.result(:add, :value), amount: 2}
        )
      ],
      output: Ref.result(:multiply)
    )
  end

  def map_flow(items, on_error) do
    items = Enum.map(items, &Map.put_new(&1, :block, false))

    JidoActionTest.FlowBuilder.new!(
      name: "step_map",
      components: [
        JidoActionTest.FlowComponent.map!(
          name: :mapped,
          collection: items,
          action: MapProbeAction,
          params: map_probe_input(),
          on_error: on_error
        )
      ],
      output: Ref.result(:mapped)
    )
  end

  def map_reduce_flow(mode) do
    items =
      case mode do
        :success ->
          [%{value: :zero, outcome: :ok}, %{value: :one, outcome: :ok}]

        :with_error ->
          [%{value: :zero, outcome: :ok}, %{value: :one, outcome: {:error, "failed"}}]
      end
      |> Enum.map(&Map.put_new(&1, :block, false))

    JidoActionTest.FlowBuilder.new!(
      name: "stepwise_map_reduce",
      components: [
        JidoActionTest.FlowComponent.map!(
          name: :mapped,
          collection: items,
          action: MapProbeAction,
          params: map_probe_input(),
          on_error: :collect_errors
        ),
        JidoActionTest.FlowComponent.reduce!(
          name: :reduced,
          collection: Ref.result(:mapped),
          initial: %{values: [], indexes: []},
          action: ReduceProbeAction,
          params: %{
            accumulator: Ref.accumulator(),
            item: Ref.item(:value),
            index: Ref.item_index(),
            item_id: Ref.item_id()
          }
        )
      ],
      output: Ref.result(:reduced)
    )
  end

  def map_probe_input do
    %{
      test_pid: Ref.context(:test_pid),
      index: Ref.item_index(),
      value: Ref.item(:value),
      outcome: Ref.item(:outcome),
      block: Ref.item(:block)
    }
  end

  def diamond_flow(action) do
    branch_input = fn side ->
      %{side: side}
    end

    JidoActionTest.FlowBuilder.new!(
      name: "step_diamond",
      components: [
        JidoActionTest.FlowComponent.step!(
          name: :right,
          action: action,
          params: branch_input.(:right)
        ),
        JidoActionTest.FlowComponent.step!(
          name: :left,
          action: action,
          params: branch_input.(:left)
        ),
        JidoActionTest.FlowComponent.step!(
          name: :merge,
          action: EchoParamsAction,
          params: %{
            left: Ref.result(:left, :side),
            right: Ref.result(:right, :side)
          }
        )
      ],
      output: Ref.result(:merge)
    )
  end

  def probe_diamond_flow do
    branch_input = fn side ->
      %{
        probe: Ref.context(:probe),
        side: side,
        test_pid: Ref.context(:test_pid)
      }
    end

    JidoActionTest.FlowBuilder.new!(
      name: "step_probe_diamond",
      components: [
        JidoActionTest.FlowComponent.step!(
          name: :right,
          action: ConcurrencyProbeAction,
          params: branch_input.(:right)
        ),
        JidoActionTest.FlowComponent.step!(
          name: :left,
          action: ConcurrencyProbeAction,
          params: branch_input.(:left)
        ),
        JidoActionTest.FlowComponent.step!(
          name: :merge,
          action: EchoParamsAction,
          params: %{
            left: Ref.result(:left, :side),
            right: Ref.result(:right, :side)
          }
        )
      ],
      output: Ref.result(:merge)
    )
  end

  def wide_flow(node_count) do
    names = Enum.map(1..node_count, &node_name/1)

    components =
      names
      |> Enum.reverse()
      |> Enum.map(fn name ->
        JidoActionTest.FlowComponent.step!(
          name: name,
          action: EchoParamsAction,
          params: %{name: name}
        )
      end)

    output = Map.new(names, &{&1, Ref.result(&1)})

    JidoActionTest.FlowBuilder.new!(
      name: "wide_step_flow",
      components: components,
      output: output
    )
  end

  def serial_flow(node_count) do
    components =
      Enum.map(1..node_count, fn index ->
        params =
          if index == 1 do
            %{value: 0, amount: 1}
          else
            %{value: Ref.result(node_name(index - 1), :value), amount: 1}
          end

        JidoActionTest.FlowComponent.step!(name: node_name(index), action: Add, params: params)
      end)

    JidoActionTest.FlowBuilder.new!(
      name: "serial_step_flow_#{node_count}",
      components: components,
      output: Ref.result(node_name(node_count))
    )
  end

  def flow_execution_paths(module, input) do
    flow = module.flow()
    instruction = Instruction.new!(target: module, params: input)

    parent =
      JidoActionTest.FlowBuilder.new!(
        name: "parent_#{System.unique_integer([:positive])}",
        components: [
          JidoActionTest.FlowComponent.subflow!(name: :inner, flow: module, params: Ref.input([]))
        ],
        output: Ref.result(:inner)
      )

    [
      flow_value: fn -> Exec.run(flow, input, %{}) end,
      flow_module: fn -> Exec.run(module, input, %{}) end,
      flow_instruction: fn -> Exec.run(instruction, %{}, %{}) end,
      subflow: fn -> Exec.run(parent, input, %{}) end
    ]
  end

  def blocking_execution_forms(module, owner) do
    flow = module.flow()

    action_instruction =
      Instruction.new!(target: BlockingAction, params: %{value: :action_instruction})

    flow_instruction =
      Instruction.new!(
        target: module,
        params: %{value: :flow_instruction},
        context: %{test_pid: owner}
      )

    parent =
      JidoActionTest.FlowBuilder.new!(
        name: "blocking_parent_flow",
        components: [
          JidoActionTest.FlowComponent.subflow!(
            name: "child",
            flow: module,
            params: %{value: Ref.input(:value)}
          )
        ],
        output: Ref.result("child")
      )

    [
      action: {BlockingAction, %{value: :action}, %{test_pid: owner}},
      action_instruction: {action_instruction, %{}, %{test_pid: owner}},
      flow_value: {flow, %{value: :flow_value}, %{test_pid: owner}},
      flow_module: {module, %{value: :flow_module}, %{test_pid: owner}},
      flow_instruction: {flow_instruction, %{}, %{}},
      subflow: {parent, %{value: :subflow}, %{test_pid: owner}}
    ]
  end

  def node_name(index) do
    "node_#{index |> Integer.to_string() |> String.pad_leading(4, "0")}"
  end
end

defmodule JidoActionTest.Fixtures.Transforms do
  @moduledoc false

  def count(value, kind, _opts) do
    if counter = Process.whereis(__MODULE__),
      do: Agent.update(counter, &Map.update(&1, kind, 1, fn count -> count + 1 end))

    transformed =
      case kind do
        :input -> Map.update(value, :input_passes, 1, &(&1 + 1))
        :invalid_input -> :invalid
        :output -> Map.update(value, :output_passes, 1, &(&1 + 1))
        :envelope_output -> value
        :invalid_output -> :invalid
      end

    {:ok, transformed}
  end

  def calls(kind), do: Agent.get(__MODULE__, &Map.get(&1, kind, 0))
  def reset, do: Agent.update(__MODULE__, fn _counts -> %{} end)
end

defmodule JidoActionTest.Fixtures.Iterator do
  @moduledoc false

  alias Jido.Flow.Ref

  @state_schema_recorder :jido_flow_iterator_runtime_state_schema_recorder

  alias JidoActionTest.Fixtures.Increment

  def record_state_transform(value, _opts) do
    if owner = Process.whereis(@state_schema_recorder) do
      send(owner, {:state_schema_transform, value})
    end

    {:ok, Map.update!(value, :count, &(&1 + 100))}
  end

  def register_state_schema_recorder(pid) when is_pid(pid) do
    Process.register(pid, @state_schema_recorder)
  end

  def iterator_flow(opts) do
    action = Keyword.get(opts, :action, Increment)
    schema = Keyword.get(opts, :schema, Zoi.map())

    input =
      Keyword.get(opts, :input, %{count: Ref.state(:count), index: Ref.iteration_index()})

    initial = Keyword.fetch!(opts, :initial)
    update = Keyword.get(opts, :update, %{count: Ref.body_result(:count)})
    completion = Keyword.fetch!(opts, :completion)
    max_iterations = Keyword.fetch!(opts, :max_iterations)

    iterator =
      JidoActionTest.FlowComponent.iterate!(
        name: :count,
        action: action,
        params: input,
        state: [schema: schema, initial: initial, update: update],
        completion: completion,
        max_iterations: max_iterations
      )

    JidoActionTest.FlowBuilder.new!(
      name: "iterator_runtime",
      components: [iterator],
      output: Ref.result(:count)
    )
  end

  def eq(left, right), do: %Jido.Expr{operator: :==, operands: [left, right]}
  def gte(left, right), do: %Jido.Expr{operator: :>=, operands: [left, right]}
end
