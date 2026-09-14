defmodule JidoTest.System.Report do
  @moduledoc false
  use GenServer

  def init(_opts) do
    Process.register(self(), __MODULE__)
    {:ok, %{rows: [], evidence: %{}}}
  end

  def handle_call({:evidence, key, evidence}, _from, state),
    do: {:reply, :ok, %{state | evidence: Map.put(state.evidence, key, evidence)}}

  def handle_cast({:test_finished, test}, state) do
    if test.tags[:system] || test.tags[:service] do
      {evidence, remaining} =
        Map.pop(state.evidence, {test.module, test.name}, %{observed: false})

      row =
        Map.merge(evidence, %{
          module: inspect(test.module),
          test: to_string(test.name),
          adapter: test.tags[:adapter],
          service_profile: test.tags[:service_profile],
          seed: ExUnit.configuration()[:seed],
          status: status(test.state),
          duration_us: test.time,
          file: Path.relative_to_cwd(test.tags.file),
          line: test.tags.line
        })

      {:noreply, %{state | rows: [row | state.rows], evidence: remaining}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:suite_finished, _timings}, %{rows: []} = state), do: {:noreply, state}

  def handle_cast({:suite_finished, _timings}, state) do
    path =
      Path.join(["tmp", "system-runs", "#{System.os_time(:microsecond)}-#{System.pid()}.json"])

    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      Jason.encode!(%{schema_version: 1, scenarios: Enum.reverse(state.rows)}, pretty: true)
    )

    IO.puts("System report: #{Path.expand(path)}")
    {:noreply, state}
  end

  def handle_cast(_event, rows), do: {:noreply, rows}

  def save(context, evidence) do
    entries = Enum.reverse(evidence.events)
    starts = Enum.filter(entries, fn {_, event, _, _} -> List.last(event) == :start end)

    terminals =
      for entry = {_, event, _, _} <- entries,
          List.last(event) in [:stop, :exception],
          do: span_key(entry)

    ended = Enum.frequencies(terminals)

    {interrupted, _ended} =
      Enum.reduce(starts, {[], ended}, fn entry, {missing, remaining} ->
        key = span_key(entry)

        if Map.get(remaining, key, 0) > 0,
          do: {missing, Map.update!(remaining, key, &(&1 - 1))},
          else: {[operation(entry) | missing], remaining}
      end)

    revisions =
      for {_, _, measures, metadata} <- entries,
          revision = measures[:revision_after] || measures[:state_version_after],
          is_integer(revision),
          do: %{agent_id: metadata[:agent_id], revision: revision}

    report = %{
      observed: true,
      fault_boundary: context[:scenario] || to_string(context.test),
      model_seed: context[:model_seed],
      revisions: revisions |> Enum.uniq() |> Enum.take(-32),
      effect_attempts: evidence.effect_attempts,
      effect_ids: evidence.effect_ids |> MapSet.to_list() |> Enum.sort() |> Enum.take(32),
      interrupted_operations: Enum.take(interrupted, 32),
      interrupted_count: length(interrupted),
      event_counts:
        Enum.frequencies_by(entries, fn {_, event, _, _} -> Enum.join(event, ".") end),
      log_count: length(evidence.logs),
      measurements: evidence.measurements,
      resource_counts: %{
        observed_emitters: entries |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length(),
        live_emitters_after_cleanup:
          entries |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.count(&Process.alive?/1),
        vm_processes_after_cleanup: :erlang.system_info(:process_count),
        vm_memory_bytes_after_cleanup: :erlang.memory(:total)
      }
    }

    File.write!(evidence_path(context.tmp_dir), Jason.encode!(report))
    # A missing or crashed reporter fails scenario cleanup instead of silently
    # dropping evidence. ExUnit sends test_finished only after this callback.
    :ok = GenServer.call(__MODULE__, {:evidence, {context.module, context.test}, report})
  end

  defp span_key({pid, event, _, meta}),
    do: {pid, Enum.drop(event, -1), meta[:turn_id], meta[:operation], meta[:topology_operation]}

  defp operation({pid, event, _, meta}),
    do: %{
      emitter: inspect(pid),
      boundary: Enum.join(Enum.drop(event, -1), "."),
      turn_id: meta[:turn_id],
      activation_id: meta[:activation_id],
      operation: meta[:operation] || meta[:topology_operation]
    }

  defp evidence_path(directory), do: Path.join(directory, "system-evidence.json")
  defp status(nil), do: :passed
  defp status({status, _details}), do: status
end
