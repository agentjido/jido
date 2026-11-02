defmodule JidoActionTest.Fixtures.Execution.SystemLoad do
  @moduledoc false

  alias Jido.Expr
  alias Jido.Flow.Ref

  defmodule HeldWork do
    use Jido.Action, name: "system_load_held_work"

    @impl true
    def run(%{id: id, value: _value} = params, %{observer: observer, run_ref: ref, ledger: ledger}) do
      Agent.update(ledger, fn state ->
        active = state.active + 1
        %{state | active: active, peak: max(state.peak, active), started: [id | state.started]}
      end)

      send(observer, {ref, :ready, id, self()})

      receive do
        {^ref, :release} ->
          Agent.update(ledger, fn state ->
            %{state | active: state.active - 1, completed: [id | state.completed]}
          end)

          {:ok, Map.take(params, [:id, :value, :item_id])}

        {^ref, :fail} ->
          Agent.update(ledger, fn state -> %{state | active: state.active - 1} end)
          {:error, Jido.Action.Error.execution_error("injected held-work failure", %{id: id})}
      end
    end
  end

  defmodule CountedWork do
    use Jido.Action, name: "system_load_counted_work"

    @impl true
    def run(%{id: id, value: value}, %{ledger: ledger, run_ref: ref, observer: observer}) do
      Agent.update(ledger, fn state ->
        %{state | started: [{ref, id} | state.started], completed: [{ref, id} | state.completed]}
      end)

      send(observer, {ref, :worker_done, id, self()})
      {:ok, %{id: id, value: value}}
    end
  end

  def initial_ledger, do: %{active: 0, peak: 0, started: [], completed: []}

  def snapshot(ledger), do: Agent.get(ledger, & &1)

  def composed_flow do
    JidoActionTest.FlowBuilder.new!(
      name: "system_composed_flow",
      components: [
        JidoActionTest.FlowComponent.step!(
          name: "left",
          action: HeldWork,
          params: %{id: :left, value: Ref.input(:left)}
        ),
        JidoActionTest.FlowComponent.step!(
          name: "right",
          action: HeldWork,
          params: %{id: :right, value: Ref.input(:right)}
        ),
        JidoActionTest.FlowComponent.map!(
          name: "mapped",
          action: HeldWork,
          collection: Ref.input(:items),
          params: %{id: Ref.item(), value: Ref.item()},
          needs: ["left", "right"]
        )
      ],
      output: %{
        left: Ref.result("left", :value),
        right: Ref.result("right", :value),
        mapped: Ref.result("mapped")
      }
    )
  end

  def wide_flow(count) do
    JidoActionTest.FlowBuilder.new!(
      name: "load_wide_flow",
      components:
        for id <- 1..count do
          JidoActionTest.FlowComponent.step!(
            name: "work_#{id}",
            action: HeldWork,
            params: %{id: id, value: id}
          )
        end,
      output: %{values: for(id <- 1..count, do: Ref.result("work_#{id}", :value))}
    )
  end

  def map_flow do
    JidoActionTest.FlowBuilder.new!(
      name: "load_map_flow",
      components: [
        JidoActionTest.FlowComponent.map!(
          name: "mapped",
          collection: Ref.input(:items),
          action: HeldWork,
          params: %{id: Ref.item(), value: Ref.item()}
        )
      ],
      output: %{mapped: Ref.result("mapped")}
    )
  end

  def map_flow_with_ids do
    JidoActionTest.FlowBuilder.new!(
      name: "load_map_with_ids",
      components: [
        JidoActionTest.FlowComponent.map!(
          name: "mapped",
          collection: Ref.input(:items),
          action: HeldWork,
          params: %{id: Ref.item(), value: Ref.item(), item_id: Ref.item_id()}
        )
      ],
      output: %{mapped: Ref.result("mapped")}
    )
  end

  def deep_flow(count) when is_integer(count) and count > 0 do
    components =
      for index <- 1..count do
        value =
          if index == 1, do: Ref.input(:value), else: Ref.result("work_#{index - 1}", :value)

        JidoActionTest.FlowComponent.step!(
          name: "work_#{index}",
          action: CountedWork,
          params: %{id: index, value: value}
        )
      end

    JidoActionTest.FlowBuilder.new!(
      name: "load_deep_flow",
      components: components,
      output: %{value: Ref.result("work_#{count}", :value)}
    )
  end

  def diamond_flow(width) when is_integer(width) and width > 1 do
    producer_names = for index <- 1..width, do: "producer_#{index}"
    reader_names = for index <- 1..width, do: "reader_#{index}"
    producer_values = Map.new(producer_names, &{&1, Ref.result(&1, :value)})

    readers =
      for name <- reader_names do
        JidoActionTest.FlowComponent.step!(
          name: name,
          action: CountedWork,
          params: %{id: name, value: producer_values}
        )
      end

    producers =
      for name <- producer_names do
        JidoActionTest.FlowComponent.step!(
          name: name,
          action: CountedWork,
          params: %{id: name, value: Ref.result("root", :value)}
        )
      end

    root =
      JidoActionTest.FlowComponent.step!(
        name: "root",
        action: CountedWork,
        params: %{id: "root", value: Ref.input(:value)}
      )

    JidoActionTest.FlowBuilder.new!(
      name: "load_diamond_flow",
      components: readers ++ Enum.reverse(producers) ++ [root],
      output: %{readers: for(name <- reader_names, do: Ref.result(name, :value))}
    )
  end

  def counted_flow do
    JidoActionTest.FlowBuilder.new!(
      name: "load_counted_flow",
      components: [
        JidoActionTest.FlowComponent.step!(
          name: "first",
          action: CountedWork,
          params: %{id: :first, value: Ref.input(:value)}
        ),
        JidoActionTest.FlowComponent.step!(
          name: "second",
          action: CountedWork,
          params: %{id: :second, value: Ref.result("first", :value)}
        )
      ],
      output: %{value: Ref.result("second", :value)}
    )
  end

  def combined_child_flow do
    JidoActionTest.FlowBuilder.new!(
      name: "system_combined_child",
      components: [
        JidoActionTest.FlowComponent.step!(
          name: "child_work",
          action: HeldWork,
          params: %{id: :child, value: Ref.input(:value)}
        )
      ],
      output: %{value: Ref.result("child_work", :value)}
    )
  end

  defmodule CombinedChild do
    use Jido.Flow, name: "system_combined_child"

    flow do
      step "child_work",
        action: JidoActionTest.Fixtures.Execution.SystemLoad.HeldWork,
        params: %{id: :child, value: input(:value)}

      output %{value: result("child_work", :value)}
    end
  end

  def combined_flow do
    choice =
      JidoActionTest.FlowComponent.choice!(
        name: "route",
        options: [
          JidoActionTest.FlowComponent.option!(
            name: "positive",
            condition: Expr.new!(:>=, [Ref.input(:value), 0]),
            action: HeldWork,
            params: %{id: :choice, value: Ref.result("child", :value)}
          )
        ],
        fallback:
          JidoActionTest.FlowComponent.fallback!(
            action: HeldWork,
            params: %{id: :fallback, value: 0}
          )
      )

    state =
      JidoActionTest.FlowComponent.state!(
        schema: Zoi.object(%{count: Zoi.integer()}),
        initial: %{count: Ref.result("reduce", :value)},
        update: %{count: Ref.body_result(:value)}
      )

    JidoActionTest.FlowBuilder.new!(
      name: "system_all_components",
      components: [
        JidoActionTest.FlowComponent.step!(
          name: "start",
          action: HeldWork,
          params: %{id: :start, value: Ref.input(:value)}
        ),
        JidoActionTest.FlowComponent.subflow!(
          name: "child",
          flow: CombinedChild,
          params: %{value: Ref.result("start", :value)}
        ),
        choice,
        JidoActionTest.FlowComponent.map!(
          name: "mapped",
          collection: Ref.input(:items),
          action: HeldWork,
          params: %{id: Ref.item(), value: Ref.item()},
          needs: ["route"]
        ),
        JidoActionTest.FlowComponent.reduce!(
          name: "reduce",
          collection: Ref.result("mapped"),
          initial: %{value: 0},
          action: HeldWork,
          params: %{
            id: :reduce,
            value: Expr.new!(:+, [Ref.accumulator(:value), Ref.item(:value)])
          }
        ),
        JidoActionTest.FlowComponent.iterate!(
          name: "iterate",
          state: state,
          action: HeldWork,
          params: %{id: :iterate, value: Expr.new!(:+, [Ref.state(:count), 1])},
          completion: Expr.new!(:>=, [Ref.iteration_index(), 2]),
          max_iterations: 2
        )
      ],
      output: %{
        child: Ref.result("child", :value),
        route: Ref.result("route", :value),
        mapped: Ref.result("mapped"),
        total: Ref.result("reduce", :value),
        iteration: Ref.result("iterate", [:state, :count])
      }
    )
  end
end
