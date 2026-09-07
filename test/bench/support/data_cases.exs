defmodule JidoCoreBench.DataCases do
  @moduledoc false
  alias JidoCoreBench.Fixtures, as: F

  def workloads do
    codec_cases() ++ audit_cases() ++ record_cases() ++ other_cases()
  end

  defp codec_cases do
    for size <- [1, 16], op <- [:encode, :decode] do
      F.checked(
        "codec/#{op}/#{size}",
        fn _ ->
          a = F.definition(size)
          {:ok, doc, registry} = Jido.Agent.Codec.encode(a)
          {a, JSON.decode!(JSON.encode!(doc)), registry}
        end,
        fn {a, doc, r} ->
          case op do
            :encode -> Jido.Agent.Codec.encode(a, r)
            :decode -> Jido.Agent.Codec.decode(doc, r)
          end
        end,
        fn {:ok, result} ->
          case op do
            :encode -> F.equal!(length(result["routes"]), size)
            :decode -> F.equal!(result, F.definition(size))
          end
        end
      )
    end
  end

  defp audit_cases do
    records = for i <- 1..2_100, do: Jido.Plugin.Audit.record({:bench, i}, :ok, at: i)

    sizes = for n <- [1, 1_000], count <- [0, 1, 100], do: {n, count}

    for {n, count} <- sizes ++ [{1_100, 0}, {1_000, 1_000}, {1_000, 1_100}] do
      existing = Enum.take(records, n)
      incoming = Enum.slice(records, n, count)
      expected = Enum.take(existing ++ incoming, -1_000)

      F.checked(
        "audit/update/#{n}/#{count}",
        fn _ -> %{records: existing} end,
        &Jido.Plugin.Audit.update_state(&1, incoming, max_entries: 1_000),
        fn {:ok, state} -> F.equal!(state.records, expected) end
      )
    end
  end

  defp record_cases do
    id = Jido.Signal.ID.generate!()

    fixed_time =
      for explicit <- [false, true] do
        opts = if explicit, do: [id: id, at: 1], else: [at: 1]

        F.checked(
          "audit/record/explicit_#{explicit}/100",
          fn _ -> opts end,
          fn options ->
            for i <- 1..100, do: Jido.Plugin.Audit.record({:bench, i}, :ok, options)
          end,
          fn records ->
            F.equal!(
              Enum.map(records, &{&1.event, &1.outcome, &1.at, &1.metadata}),
              for(i <- 1..100, do: {{:bench, i}, :ok, 1, %{}})
            )

            ids = Enum.map(records, & &1.id)

            if explicit do
              F.equal!(ids, List.duplicate(id, 100))
            else
              F.equal!(length(Enum.uniq(ids)), 100)
              F.equal!(Enum.all?(ids, &Jido.Signal.ID.valid?/1), true)
            end
          end
        )
      end

    default_time =
      F.checked(
        "audit/record/default_time/100",
        fn _ -> [id: id] end,
        fn opts ->
          for i <- 1..100, do: Jido.Plugin.Audit.record({:bench, i}, :ok, opts)
        end,
        fn records ->
          F.equal!(
            Enum.map(records, &{&1.id, &1.event, &1.outcome, &1.metadata}),
            for(i <- 1..100, do: {id, {:bench, i}, :ok, %{}})
          )

          F.equal!(Enum.all?(records, &(is_integer(&1.at) and &1.at > 0)), true)
        end
      )

    fixed_time ++ [default_time]
  end

  defp other_cases do
    merges =
      for n <- [1, 1_000], empty <- [true, false] do
        left = Map.new(1..n, &{&1, %{left: &1, common: 0}})
        right = if empty, do: %{}, else: Map.new(1..n, &{&1, %{right: &1, common: 1}})

        expected =
          if empty, do: left, else: Map.new(1..n, &{&1, %{left: &1, right: &1, common: 1}})

        F.checked(
          "state/merge/#{n}/empty_#{empty}",
          fn _ -> {left, right} end,
          fn {a, b} -> Jido.Util.DeepMerge.merge(a, b) end,
          &F.equal!(&1, expected)
        )
      end

    spans =
      F.checked(
        "observe/span",
        fn _ -> nil end,
        fn _ -> Jido.Observe.with_span([:jido, :bench], %{}, fn -> :ok end) end,
        &F.equal!(&1, :ok)
      )

    merges ++ [spans]
  end
end
