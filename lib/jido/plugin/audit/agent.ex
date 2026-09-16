defmodule Jido.Plugin.Audit.Agent do
  @moduledoc "Owns the bounded audit field in the complete Agent state."
  use Jido.Agent.Plugin

  alias Jido.Plugin.Audit.Record

  @default_max_entries 1_000
  @state_schema Zoi.object(%{records: Zoi.list(Zoi.struct(Record)) |> Zoi.default([])})
                |> Zoi.default(%{records: []})

  @impl true
  def state_spec(opts) do
    _max_entries = max_entries!(opts)
    {:audit, @state_schema}
  end

  @impl true
  def directives(_opts), do: [Record]

  @impl true
  def reduce(reduction, opts) do
    records = Enum.filter(reduction.directives, &match?(%Record{}, &1))
    apply_records(reduction.plugin_state, records, opts)
  end

  @doc "Applies validated domain records to the bounded audit field."
  def apply_records(state, [], opts) do
    max_entries = max_entries!(opts)
    count = length(state.records)

    if count <= max_entries do
      {:ok, state}
    else
      {:ok, %{state | records: Enum.drop(state.records, count - max_entries)}}
    end
  end

  def apply_records(state, records, opts) do
    max_entries = max_entries!(opts)
    incoming_count = length(records)

    records =
      if incoming_count >= max_entries do
        Enum.take(records, -max_entries)
      else
        Enum.take(state.records, -(max_entries - incoming_count)) ++ records
      end

    {:ok, %{state | records: records}}
  end

  defp max_entries!(opts) do
    case Keyword.get(opts, :max_entries, @default_max_entries) do
      value when is_integer(value) and value > 0 ->
        value

      value ->
        raise ArgumentError,
              "Audit max_entries must be a positive integer, got: #{inspect(value)}"
    end
  end
end
