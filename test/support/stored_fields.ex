defmodule JidoActionTest.StoredFields do
  @moduledoc false

  def update(record, fields) do
    Enum.reduce(fields, record, fn
      {field, value}, record when field in ["action", "flow"] ->
        target(record, value)

      {"params", value}, record ->
        params(record, value)

      {field, value}, record
      when field in ["decision", "expander", "selector"] and not is_map(value) ->
        put_in(record[field]["target"], value)

      {field, value}, record ->
        Map.put(record, field, value)
    end)
  end

  def target(%{"call" => _} = record, value), do: put_in(record["call"]["target"], value)
  def target(record, value), do: Map.put(record, "target", value)
  def params(%{"call" => _} = record, value), do: put_in(record["call"]["params"], value)

  def params(%{"kind" => "invoke"} = record, value),
    do: put_in(record["decision"]["params"], value)

  def params(%{"kind" => "handoff"} = record, value),
    do: put_in(record["selector"]["params"], value)

  def params(record, value), do: Map.put(record, "params", value)
end
