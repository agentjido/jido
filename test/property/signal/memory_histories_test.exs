Code.require_file("../support/fuzz.exs", __DIR__)
Code.require_file("support/model.exs", __DIR__)

defmodule JidoTest.Property.Signal.MemoryHistoriesTest do
  use ExUnit.Case, async: true
  import StreamData
  alias Jido.Signal.Bus.Store.Memory
  alias JidoTest.Property.Fuzz
  alias JidoTest.Property.Signal.Model

  @paths ~w(** a.** **.a **.a.**.b b)
  for {suite, runs, bound} <- [{:property, 40, 12}, {:fuzz, 500, 40}] do
    @tag [
      {suite, true},
      fuzz_id: "memory_histories",
      max_runs: runs,
      max_run_time: if(suite == :fuzz, do: 300_000, else: 10_000),
      timeout: if(suite == :fuzz, do: 900_000, else: 90_000)
    ]
    test "#{suite}: retained records follow a required-record model", context do
      command =
        fixed_map(%{
          "op" => member_of(~w(append put delete read invalid)),
          "id" => member_of(~w(a z)),
          "path" => member_of(@paths),
          "n" => integer(0..8),
          "types" => list_of(member_of(~w(a a.b b **.x.a)), max_length: 3)
        })

      generator =
        fixed_map(%{
          "bound" => integer(1..5),
          "commands" => list_of(command, max_length: unquote(bound))
        })

      examples = [
        history(1, [
          cmd("put", "z", "a.**", 0),
          cmd("put", "a", "a.**", 0),
          append(~w(a a.b)),
          cmd("delete", "z", "a.**", 0),
          cmd("delete", "a", "a.**", 0),
          append(~w(a a.b b))
        ]),
        history(2, [
          cmd("put", "a", "**.a", 0),
          append(["**.x.a", "b"]),
          append(["a"]),
          append(["a"]),
          cmd("put", "a", "**.a", 3),
          append(["a"])
        ]),
        history(2, [
          append(~w(a b a.b)),
          cmd("read", "a", "a.**", 0),
          cmd("invalid", "a", "**", 0)
        ])
      ]

      Fuzz.check(
        "memory_histories",
        generator,
        Map.to_list(context) ++ [examples: examples],
        &check/1
      )
    end
  end

  defp history(bound, commands), do: %{"bound" => bound, "commands" => commands}

  defp cmd(op, id, path, n),
    do: %{"op" => op, "id" => id, "path" => path, "n" => n, "types" => []}

  defp append(types), do: Map.put(cmd("append", "a", "**", 0), "types", types)

  defp check(%{"bound" => bound, "commands" => commands}) do
    assert {:ok, state} = Memory.init(max_records: bound)
    initial = %{state: state, records: [], latest: 0, definitions: []}

    final =
      Enum.reduce(commands, initial, fn command, model ->
        next = step(command, model, bound)
        assert {:ok, records} = Memory.read([], next.state)
        assert records == next.records
        assert {:ok, next.latest} == Memory.latest_cursor(next.state)
        assert {:ok, next.definitions} == Memory.list_subscriptions(next.state)
        next
      end)

    assert {:ok, retained} = Memory.read([], final.state)
    assert length(retained) == length(final.records)
    ["commands-#{length(commands)}", "bound-#{bound}"]
  end

  defp step(%{"op" => "append", "types" => types}, model, bound) do
    records = for {type, i} <- Enum.with_index(types, model.latest + 1), do: Model.record(i, type)
    all = model.records ++ records
    required = fn record -> Enum.any?(model.definitions, &needs?(&1, record)) end
    remove = max(length(all) - bound, 0)
    removable = Enum.reject(all, required) |> Enum.take(remove)

    if length(removable) < remove do
      blockers =
        model.definitions
        |> Enum.filter(fn d -> Enum.any?(all, &needs?(d, &1)) end)
        |> Enum.map(& &1["id"])
        |> Enum.sort()

      assert {:error, {:store_full, ^blockers}} = Memory.append(records, model.state)
      model
    else
      assert {:ok, state} = Memory.append(records, model.state)
      %{model | state: state, records: all -- removable, latest: model.latest + length(records)}
    end
  end

  defp step(%{"op" => "put", "id" => id, "path" => path, "n" => n}, model, _) do
    definition = Model.definition(id, path, n)
    old = Enum.find(model.definitions, &(&1["id"] == id))

    error =
      cond do
        n > model.latest -> :invalid_subscription_cursor
        old && old["path"] != path -> :subscription_conflict
        old && old["cursor"] > n -> :cursor_regression
        true -> nil
      end

    if error do
      assert {:error, ^error} = Memory.put_subscription(definition, model.state)
      model
    else
      assert {:ok, state} = Memory.put_subscription(definition, model.state)

      definitions =
        if old,
          do: Enum.map(model.definitions, fn d -> if d["id"] == id, do: definition, else: d end),
          else: model.definitions ++ [definition]

      %{model | state: state, definitions: definitions}
    end
  end

  defp step(%{"op" => "delete", "id" => id}, model, _) do
    assert {:ok, state} = Memory.delete_subscription(id, model.state)
    %{model | state: state, definitions: Enum.reject(model.definitions, &(&1["id"] == id))}
  end

  defp step(%{"op" => "read", "path" => path, "n" => n}, model, _) do
    for limit <- [1, 2, :infinity] do
      expected =
        Enum.filter(model.records, &(&1["cursor"] > n and Model.matches?(&1["type"], path)))

      expected = if limit == :infinity, do: expected, else: Enum.take(expected, limit)

      assert {:ok, ^expected} =
               Memory.read([after_cursor: n, path: path, limit: limit], model.state)
    end

    model
  end

  defp step(%{"op" => "invalid"}, model, _) do
    for records <- [[nil], [:bad], [{:bad, 1}], [Model.record(model.latest + 1, "a") | :tail]] do
      assert {:error, :invalid_records} = Memory.append(records, model.state)
    end

    assert {:error, :invalid_record_cursors} =
             Memory.append([Model.record(model.latest + 2, "a")], model.state)

    assert {:error, :invalid_read_options} = Memory.read([limit: 0], model.state)
    model
  end

  defp needs?(definition, record),
    do:
      record["cursor"] > definition["cursor"] and
        Model.matches?(record["type"], definition["path"])
end
