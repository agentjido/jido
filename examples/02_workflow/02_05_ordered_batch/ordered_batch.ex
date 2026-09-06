defmodule Jido.Examples.OrderedBatch.Convert do
  @moduledoc false
  use Jido.Action, name: "workflow_batch_convert"

  def run(input, context) do
    Jido.Examples.Workflow.Observation.record(context, {:item, input.index}, input)

    if input.value < 0,
      do: {:error, Jido.Action.Error.validation_error("invalid item", index: input.index)},
      else: {:ok, %{index: input.index, value: input.value * 2}}
  end
end

defmodule Jido.Examples.OrderedBatch.Collected do
  @moduledoc "Collected errors retain one result per input position."
  use Jido.Flow, name: "workflow_batch_collect"

  flow do
    map "convert",
      collection: input(:values),
      action: Jido.Examples.OrderedBatch.Convert,
      params: %{value: item(), index: item_index()},
      on_error: :collect_errors

    output %{items: result("convert")}
  end
end

defmodule Jido.Examples.OrderedBatch.Strict do
  @moduledoc "An ordered Map feeds a serial Reduce; any item failure rejects the Turn."
  use Jido.Flow, name: "workflow_batch_strict"

  flow do
    map "convert",
      collection: input(:values),
      action: Jido.Examples.OrderedBatch.Convert,
      params: %{value: item(), index: item_index()}

    reduce "append" do
      collection result("convert")
      initial %{items: value([])}

      action [items <- accumulator(:items), item <- item()], context: context do
        Jido.Examples.Workflow.Observation.record(context, {:reduce, item.index}, %{
          items: items,
          item: item
        })

        {:ok, %{items: items ++ [item]}}
      end
    end

    output result("append")
  end
end

defmodule Jido.Examples.OrderedBatch do
  @moduledoc "One batch fixture for Map order, error policy, empty input, and serial Reduce."
  use Jido.Agent, name: "workflow_batch_agent"

  agent do
    schema Zoi.object(%{items: Zoi.list(Zoi.map()) |> Zoi.default([])})
  end

  routes do
    signal_source "/workflow"

    route "workflow.batch.collect", Jido.Examples.OrderedBatch.Collected do
      define :collect_results
    end

    route "workflow.batch.strict", Jido.Examples.OrderedBatch.Strict do
      define :convert_all
    end
  end
end
