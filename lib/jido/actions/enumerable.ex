defmodule Jido.Actions.Enumerable do
  @moduledoc """
  An action that executes another action for each element in a collection.

  The Enumerable action takes a list of items and executes a target action for each
  item, passing both the item and its index as parameters. This is useful for batch
  processing, data transformation, or applying operations to collections within the
  agent system.

  ## Parameters

  * `action` - The action module to execute for each item
  * `items` - List of items to process (minimum: 1 item)
  * `params` - Base parameters to pass to each execution (merged with item data)
  * `item_key` - Key name to use for the current item (default: :item)
  * `index_key` - Key name to use for the current index (default: :index)
  * `current_index` - Current item index (internal, starts at 0)

  ## Examples

      # Process a list of user IDs with a notification action
      %Instruction{
        action: Jido.Actions.Enumerable,
        params: %{
          action: MyApp.Actions.SendNotification,
          items: [123, 456, 789],
          params: %{type: "welcome", template: "user_welcome"},
          item_key: :user_id
        }
      }

      # Transform a list of data with custom keys
      %Instruction{
        action: Jido.Actions.Enumerable,
        params: %{
          action: MyApp.Actions.ProcessData,
          items: ["file1.txt", "file2.txt"],
          params: %{operation: "parse"},
          item_key: :filename,
          index_key: :position
        }
      }

  ## Execution Flow

  The Enumerable action creates a sequential chain where each iteration:
  1. Takes the current item from the list
  2. Merges it with base parameters using the specified keys
  3. Executes the target action with the merged parameters
  4. Enqueues the next iteration (if more items remain)

  ## Parameter Merging

  For each item, the action creates merged parameters by:
  1. Starting with the base `params`
  2. Adding the current item using `item_key`
  3. Adding the current index using `index_key`

  Example merged params:
  ```elixir
  # Base params: %{type: "welcome"}
  # Item: 123, Index: 0
  # Result: %{type: "welcome", item: 123, index: 0}
  ```

  ## Return Value

  Each iteration returns metadata about the current execution:
  * `index` - Current item index (0-based)
  * `total` - Total number of items to process
  * `action` - The target action being executed
  * `item` - Current item being processed
  * `final` - Present and `true` only on the last iteration
  """

  use Jido.Action,
    name: "enumerable",
    description: "Executes another action for each element in a collection",
    schema: [
      action: [type: :atom, required: true, doc: "Action module to execute for each item"],
      items: [type: {:list, :any}, required: true, doc: "List of items to process (minimum: 1)"],
      params: [type: :map, default: %{}, doc: "Base parameters merged with item data"],
      item_key: [type: :atom, default: :item, doc: "Key name for current item"],
      index_key: [type: :atom, default: :index, doc: "Key name for current index"],
      current_index: [type: :non_neg_integer, default: 0, doc: "Current item index (internal)"]
    ],
    output_schema: [
      index: [type: :non_neg_integer, required: true, doc: "Current item index"],
      total: [type: :pos_integer, required: true, doc: "Total number of items"],
      action: [type: :atom, required: true, doc: "Target action being executed"],
      item: [type: :any, required: true, doc: "Current item being processed"],
      final: [type: :boolean, doc: "Present and true only on last iteration"]
    ]

  alias Jido.Agent.Directive.Enqueue

  @impl true
  def run(%{items: []}, _ctx),
    do: {:error, "Items list cannot be empty"}

  @impl true
  def run(%{items: items, current_index: i}, _ctx) when i >= length(items),
    do: {:error, "Current index (#{i}) exceeds items length (#{length(items)})"}

  @impl true
  def run(%{action: mod, items: items, params: base_params, current_index: i} = args, _ctx) do
    item_key = Map.get(args, :item_key, :item)
    index_key = Map.get(args, :index_key, :index)
    total = length(items)
    current_item = Enum.at(items, i)

    # Merge base params with current item and index
    merged_params =
      base_params
      |> Map.put(item_key, current_item)
      |> Map.put(index_key, i)

    result_meta = %{
      index: i,
      total: total,
      action: mod,
      item: current_item,
      final: i == total - 1
    }

    next = if i < total - 1, do: [enqueue(__MODULE__, %{args | current_index: i + 1})], else: []

    {:ok, result_meta, [enqueue(mod, merged_params) | next]}
  end

  defp enqueue(mod, params), do: %Enqueue{action: mod, params: params, context: %{}}
end
