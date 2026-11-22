defmodule Jido.Examples.OrderedBatch do
  @moduledoc "One batch fixture for Map order, error policy, empty input, and serial Reduce."

  alias Jido.Joi

  use Jido.Agent, name: "workflow_batch_agent"

  state do
    schema Joi.object(%{items: Joi.list(Joi.map()) |> Joi.default([])})
  end

  routes do
    signal_source "/workflow"

    route "workflow.batch.collect", Jido.Examples.OrderedBatch.Collected, as: :collect_results

    route "workflow.batch.strict", Jido.Examples.OrderedBatch.Strict, as: :convert_all
  end
end

defmodule Jido.Examples.OrderedBatch.Convert do
  @moduledoc false

  alias Jido.Joi

  use Jido.Action,
    name: "workflow_batch_convert",
    schema: Joi.object(%{value: Joi.integer(), index: Joi.integer() |> Joi.min(0)})

  @impl true
  def run(input, _context) do
    if input.value < 0,
      do: {:error, Jido.Error.validation_error("invalid item", index: input.index)},
      else: {:ok, %{index: input.index, value: input.value * 2}}
  end
end

defmodule Jido.Examples.OrderedBatch.Collected do
  @moduledoc "Collected errors retain one result per input position."

  alias Jido.Joi

  use Jido.Flow,
    name: "workflow_batch_collect",
    schema: Joi.object(%{values: Joi.list(Joi.integer())}),
    output_schema: Joi.object(%{items: Joi.list(Joi.map())})

  flow do
    map "convert",
      collection: input(:values),
      action: Jido.Examples.OrderedBatch.Convert,
      params: %{value: item(), index: item_index()},
      on_error: :collect_errors

    output %{items: result("convert")}
  end
end

defmodule Jido.Examples.OrderedBatch.Append do
  @moduledoc false
  use Jido.Action,
    name: "workflow_batch_append"

  def run(%{items: items, item: item}, _context), do: {:ok, %{items: items ++ [item]}}
end

defmodule Jido.Examples.OrderedBatch.Strict do
  @moduledoc "An ordered Map feeds a serial Reduce; any item failure rejects the Turn."

  alias Jido.Joi

  use Jido.Flow,
    name: "workflow_batch_strict",
    schema: Joi.object(%{values: Joi.list(Joi.integer())}),
    output_schema: Joi.object(%{items: Joi.list(Joi.map())})

  flow do
    map "convert",
      collection: input(:values),
      action: Jido.Examples.OrderedBatch.Convert,
      params: %{value: item(), index: item_index()}

    reduce "append" do
      collection result("convert")
      initial %{items: value([])}

      action Jido.Examples.OrderedBatch.Append
      params %{items: accumulator(:items), item: item()}
    end

    output result("append")
  end
end
