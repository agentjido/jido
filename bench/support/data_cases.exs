defmodule JidoCoreBench.DataCases do
  @moduledoc false
  alias JidoCoreBench.Fixtures, as: F

  def workloads(sizes) do
    Enum.flat_map(sizes, &thread_cases/1) ++ codec_cases() ++ audit_cases() ++ other_cases()
  end

  defp thread_cases(n) do
    entries = for i <- 1..n, do: %{id: "entry-#{i}", at: 1, kind: :note, payload: %{n: i}}

    for op <- [:append_one, :append_batch, :last, :slice, :normalize] do
      F.checked(
        "thread/#{op}/#{n}",
        fn _ -> Jido.Thread.append(Jido.Thread.new(id: "bench-thread", now: 1), entries) end,
        fn thread ->
          case op do
            :append_one -> Jido.Thread.append(thread, hd(entries))
            :append_batch -> Jido.Thread.append(thread, entries)
            :last -> Jido.Thread.last(thread)
            :slice -> Jido.Thread.slice(thread, div(n, 2), n - 1)
            :normalize -> Jido.Thread.EntryNormalizer.normalize_many(entries, n, 1)
          end
        end,
        fn result ->
          case op do
            :last ->
              F.equal!({result.seq, result.payload}, {n - 1, %{n: n}})

            :slice ->
              F.equal!(Enum.map(result, & &1.seq), Enum.to_list(div(n, 2)..(n - 1)))

            :normalize ->
              F.equal!(
                Enum.map(result, &{&1.seq, &1.payload}),
                for(i <- 1..n, do: {n + i - 1, %{n: i}})
              )

            _ ->
              count = if op == :append_one, do: n + 1, else: n * 2

              F.equal!(
                {result.rev, Jido.Thread.entry_count(result), Enum.map(result.entries, & &1.seq)},
                {count, count, Enum.to_list(0..(count - 1))}
              )
          end
        end
      )
    end
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
    record = Jido.Plugin.Audit.record(:bench, :ok)

    for n <- [1, 1_000], count <- [0, 1, 100] do
      F.checked(
        "audit/update/#{n}/#{count}",
        fn _ -> %{records: List.duplicate(record, n)} end,
        &Jido.Plugin.Audit.update_state(&1, List.duplicate(record, count), max_entries: 1_000),
        fn {:ok, state} ->
          F.equal!(state.records, List.duplicate(record, min(n + count, 1_000)))
        end
      )
    end
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
