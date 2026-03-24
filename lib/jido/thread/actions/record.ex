defmodule Jido.Thread.Actions.Record do
  @moduledoc """
  Append entries to the thread stored in agent state.

  This action powers the default `thread.entries.record` signal route exposed by
  `Jido.Thread.Plugin`.
  """

  use Jido.Action,
    name: "thread_record",
    description: "Record one or more entries in the agent thread",
    schema: [
      entries: [type: {:list, :map}, required: true, doc: "Entries to append to the thread"]
    ]

  alias Jido.Thread

  @spec run(%{entries: [map()]}, map()) ::
          {:ok, %{__thread__: Thread.t()}} | {:error, Jido.Error.ValidationError.t()}
  def run(%{entries: []}, _context) do
    {:error, Jido.Error.validation_error("entries must not be empty", field: :entries)}
  end

  def run(%{entries: entries}, context) when is_list(entries) do
    thread = Map.get(context.state, :__thread__) || Thread.new()
    {:ok, %{__thread__: Thread.append(thread, entries)}}
  end
end
