defmodule Jido.Test.Perf.Signal.SelectorCases do
  @moduledoc false

  alias Jido.Signal
  alias Jido.Signal.{Bus, Router}
  alias Jido.Signal.Bus.Selector
  alias Jido.Signal.Router.Index
  alias Jido.Test.Perf.Signal.Helpers
  import Helpers, only: [plain: 5, stateful: 6, expect!: 2]

  @type_path "bench.selector.changed"

  def workloads(size) do
    Enum.flat_map([:source, :subject, :source_subject], &lookup(size, &1)) ++
      publication(size) ++ [churn(size)]
  end

  defp lookup(size, kind) do
    count = size * 128

    routes =
      for index <- 1..count do
        {:ok, match} = Selector.compile(fields(kind, index))
        {path(index), match, "selector#{index}"}
      end

    router = Router.new!(routes)
    selected = event(kind, count)

    for {outcome, signal, expected} <- [
          {:hit, selected, ["selector#{count}"]},
          {:miss, miss(selected, kind), []}
        ] do
      plain(
        "router/selector_#{kind}_#{outcome}",
        {router, signal},
        fn _ -> Index.lookup(router, signal.type, signal) end,
        &expect!(&1, expected),
        %{
          type_candidates: count,
          selector_fields: Keyword.keys(fields(kind, count)),
          matching_subscriptions: length(expected)
        }
      )
    end
  end

  defp publication(size) do
    count = size * 16
    selected = event(:source_subject, count)

    for {outcome, signal} <- [{:hit, selected}, {:miss, miss(selected, :source_subject)}] do
      stateful(
        "bus/selector_#{outcome}",
        signal,
        fn state ->
          bus = Helpers.bus(state, 1)

          for index <- 1..count do
            {:ok, _} =
              Bus.subscribe(bus, path(index),
                subscription_id: "selector#{index}",
                selector: fields(:source_subject, index)
              )
          end

          Map.put(state, :bus, bus)
        end,
        fn state ->
          {:ok, records} = Bus.publish(state.bus, [signal])
          records
        end,
        fn records, _state ->
          Helpers.records(records, [signal])

          if outcome == :hit do
            receive do
              {:signal, ^signal} -> :ok
            after
              0 -> raise "selected Signal was not delivered"
            end
          end

          Helpers.empty_mailbox!()
        end,
        %{
          subscriptions: count,
          selector_fields: [:source, :subject],
          matching_subscriptions: if(outcome == :hit, do: 1, else: 0)
        }
      )
    end
  end

  defp churn(size) do
    count = size * 16
    selectors = for index <- 1..count, do: {"selector#{index}", fields(:source_subject, index)}

    stateful(
      "bus/selector_churn",
      selectors,
      fn state -> Map.put(state, :bus, Helpers.bus(state, 1)) end,
      fn state ->
        Enum.each(selectors, fn {id, selector} ->
          {:ok, ^id} =
            Bus.subscribe(state.bus, @type_path, subscription_id: id, selector: selector)

          :ok = Bus.unsubscribe(state.bus, id)
        end)
      end,
      fn result, state ->
        expect!(result, :ok)
        current = :sys.get_state(state.bus)
        expect!(current.subscriptions, %{})
        expect!(current.monitors, %{})
        expect!(Router.empty?(current.router), true)
        Helpers.empty_mailbox!()
      end,
      %{subscription_pairs: count, selector_fields: [:source, :subject]}
    )
  end

  defp path(index) when rem(index, 2) == 0, do: "bench.selector.*"
  defp path(_index), do: @type_path

  defp fields(:source, index), do: [source: "/benchmark/source#{index}"]
  defp fields(:subject, index), do: [subject: "item#{index}"]

  defp fields(:source_subject, index),
    do: [source: "/benchmark/source#{index}", subject: "item#{index}"]

  defp event(kind, index) do
    selector = fields(kind, index)

    Signal.new!(@type_path, %{"value" => 42},
      id: "selector-benchmark",
      source: Keyword.get(selector, :source, "/benchmark"),
      subject: Keyword.get(selector, :subject, "unselected-subject")
    )
  end

  defp miss(signal, :source), do: %{signal | source: "/benchmark/unmatched"}
  defp miss(signal, _kind), do: %{signal | subject: "unmatched-subject"}
end
