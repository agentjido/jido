defmodule JidoCoreBench.Measure do
  @moduledoc false
  @timeout 30_000

  def timing(workload, warmup, samples) do
    isolated(fn ->
      for _ <- 1..warmup, do: invoke(workload)

      measurements =
        for _ <- 1..samples do
          with_prepared(workload, %{}, fn prepared ->
            # Remove garbage from untimed setup before the operation starts.
            :erlang.garbage_collect(self())
            {:reductions, before_reductions} = Process.info(self(), :reductions)
            before_time = System.monotonic_time()
            result = workload.run.(prepared)
            elapsed = System.monotonic_time() - before_time
            {:reductions, after_reductions} = Process.info(self(), :reductions)
            :ok = check_result(workload, prepared, result)

            {System.convert_time_unit(elapsed, :native, :nanosecond),
             after_reductions - before_reductions}
          end)
        end

      %{
        wall_ns: distribution(Enum.map(measurements, &elem(&1, 0))),
        caller_reductions: distribution(Enum.map(measurements, &elem(&1, 1)))
      }
    end)
  end

  def resources(workload, count \\ 1) when is_integer(count) and count > 0 do
    samples = for _ <- 1..count, do: isolated(fn -> trace_resources(workload) end)
    %{samples: samples, median: median_fields(samples)}
  end

  def retained(workload) do
    isolated(fn ->
      with_prepared(workload, %{}, fn prepared ->
        result = workload.run.(prepared)
        :ok = check_result(workload, prepared, result)

        Map.new(workload.retained.(prepared, result), fn {name, term} ->
          {name, term_size(term)}
        end)
      end)
    end)
  end

  defp median_fields([first | _] = samples) do
    Map.new(first, fn {key, value} ->
      values = Enum.map(samples, &Map.fetch!(&1, key))

      median =
        cond do
          is_map(value) -> median_fields(values)
          is_number(value) -> distribution(values).median
          is_nil(value) -> nil
        end

      {key, median}
    end)
  end

  def term_size(term) do
    word = :erlang.system_info(:wordsize)
    local = :erts_debug.size(term) * word
    flat = :erts_debug.flat_size(term) * word

    # Bound the flattened heap before the transfer. Shared binary payloads do
    # not form part of this heap estimate; the encoded size reports them too.
    if flat > 64 * 1_048_576, do: raise("term transfer exceeds the 64 MiB heap bound")

    transfer =
      isolated(
        fn ->
          receive do
            {:term, copied} ->
              {:memory, memory} = Process.info(self(), :memory)
              {:binary, binaries} = Process.info(self(), :binary)

              %{
                copied_flat_heap_bytes: :erts_debug.flat_size(copied) * word,
                receiver_memory_bytes: memory,
                observed_receiver_binary_bytes:
                  binaries
                  |> Map.new(fn {id, bytes, _} -> {id, bytes} end)
                  |> Map.values()
                  |> Enum.sum()
              }
          end
        end,
        fn pid -> send(pid, {:term, term}) end
      )

    Map.merge(transfer, %{
      local_heap_bytes: local,
      flat_heap_bytes: flat,
      external_bytes: :erlang.external_size(term)
    })
  end

  def distribution(values) do
    sorted = Enum.sort(values)
    count = length(sorted)

    %{
      samples: values,
      min: hd(sorted),
      median: Enum.at(sorted, div(count, 2)),
      p95: Enum.at(sorted, max(ceil(count * 0.95) - 1, 0)),
      max: List.last(sorted),
      mean: Enum.sum(sorted) / count
    }
  end

  defp invoke(workload) do
    with_prepared(workload, %{}, fn prepared ->
      result = workload.run.(prepared)
      :ok = check_result(workload, prepared, result)
    end)
  end

  defp check_result(workload, prepared, result) do
    :ok = workload.check.(result)
    Map.get(workload, :verify, fn _, _ -> :ok end).(prepared, result)
  end

  defp with_prepared(workload, context, fun) do
    prepared = workload.setup.(context)

    try do
      fun.(prepared)
    after
      Map.get(workload, :cleanup, fn _ -> :ok end).(prepared)
    end
  end

  defp trace_resources(workload) do
    observer = self()
    table = :ets.new(:bench_owned, [:set, :private])

    supervisor =
      Process.whereis(JidoCoreBench.TaskSupervisor) || raise "benchmark supervisor missing"

    {caller, caller_ref} =
      spawn_monitor(fn ->
        receive do
          :bench_go ->
            try do
              with_prepared(workload, %{bench_observer: observer}, fn prepared ->
                result = workload.run.(prepared)
                JidoCoreBench.Fixtures.barrier(%{bench_observer: observer})
                :ok = check_result(workload, prepared, result)
              end)

              send(observer, {:bench_result, :ok})
            rescue
              error -> send(observer, {:bench_result, {:error, Exception.message(error)}})
            catch
              kind, reason -> send(observer, {:bench_result, {:error, inspect({kind, reason})}})
            end
        end
      end)

    state = %{
      caller: caller,
      caller_ref: caller_ref,
      table: table,
      pending: [],
      result: nil,
      caller_down: false,
      observations: 0,
      reductions: %{},
      collections: %{},
      observed_peak: %{
        process_memory_bytes: 0,
        process_heap_bytes: 0,
        shared_binary_bytes: 0,
        vm_total_bytes: 0,
        vm_processes_bytes: 0,
        vm_binary_bytes: 0,
        live_owned: 0,
        mailbox_messages: 0
      }
    }

    try do
      flags = [:procs, :garbage_collection, :set_on_spawn, {:tracer, self()}]
      :erlang.trace(supervisor, true, flags)
      :erlang.trace(caller, true, flags)
      state = observe(state)
      send(caller, :bench_go)
      state = collect(state)

      case state.result do
        :ok -> :ok
        other -> raise "resource caller failed: #{inspect(other)}"
      end

      state = finish_owned(state)

      %{
        owned_process_starts: :ets.info(table, :size),
        owned_remaining: 0,
        observations: state.observations,
        observed_peak: state.observed_peak,
        observed_helper_reductions:
          Enum.sum(for {pid} <- :ets.tab2list(table), do: Map.get(state.reductions, pid, 0)),
        observed_caller_reductions: Map.get(state.reductions, caller, 0),
        owned_gc_count:
          Enum.sum(
            for pid <- [caller | Enum.map(:ets.tab2list(table), &elem(&1, 0))],
                do: Map.get(state.collections, pid, 0)
          ),
        helper_reductions: nil,
        exact_peak_bytes: nil
      }
    after
      try do
        stop_processes([caller])
        stop_descendants(fence(state))
      after
        :erlang.trace(supervisor, false, [:all])
        Process.demonitor(caller_ref, [:flush])
        :ets.delete(table)
      end
    end
  end

  # Stop the caller first, then drain traces before stopping its descendants.
  # Repeat for any child starts delivered during termination. Return only after
  # monitors confirm that every observed process has stopped.
  defp stop_descendants(state) do
    known = :ets.tab2list(state.table)
    stop_processes(Enum.map(known, &elem(&1, 0)))
    state = fence(state)

    if :ets.info(state.table, :size) != length(known), do: stop_descendants(state)
    :ok
  end

  defp stop_processes(pids) do
    monitors = Enum.map(pids, &{&1, Process.monitor(&1)})
    Enum.each(pids, &Process.exit(&1, :kill))
    Enum.each(monitors, fn {pid, ref} -> await_down(pid, ref) end)
  end

  defp await_down(pid, ref) do
    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      @timeout -> raise "owned process did not stop: #{inspect(pid)}"
    end
  end

  defp collect(%{caller_down: true} = state), do: fence(state) |> observe()

  defp collect(state) do
    receive do
      message ->
        state = handle(message, state)
        state = if state.pending == [], do: state, else: release_barriers(state)
        collect(state)
    after
      @timeout -> raise "resource caller exceeded the safety limit"
    end
  end

  defp release_barriers(state) do
    state = state |> fence() |> observe()
    for {pid, ref} <- state.pending, do: send(pid, {:bench_release, ref})
    %{state | pending: []}
  end

  defp fence(state) do
    marker = :erlang.trace_delivered(:all)
    drain(marker, state)
  end

  defp drain(marker, state) do
    receive do
      {:trace_delivered, :all, ^marker} -> state
      message -> drain(marker, handle(message, state))
    after
      @timeout -> raise "trace delivery barrier missing"
    end
  end

  defp handle({:trace, _parent, :spawn, child, _mfa}, state) do
    :ets.insert_new(state.table, {child})
    state
  end

  defp handle({:bench_barrier, pid, ref}, state),
    do: %{state | pending: [{pid, ref} | state.pending]}

  defp handle({:bench_result, result}, state), do: %{state | result: result}

  defp handle({:trace, pid, event, _info}, state)
       when event in [:gc_minor_end, :gc_major_end] do
    %{state | collections: Map.update(state.collections, pid, 1, &(&1 + 1))}
  end

  defp handle({:DOWN, ref, :process, _pid, reason}, %{caller_ref: ref} = state) do
    result = if reason == :normal, do: state.result, else: {:error, inspect(reason)}
    %{state | caller_down: true, result: result}
  end

  defp handle(_message, state), do: state

  defp finish_owned(state) do
    previous = :ets.info(state.table, :size)

    for {pid} <- :ets.tab2list(state.table) do
      await_down(pid, Process.monitor(pid))
    end

    state = fence(state)
    if :ets.info(state.table, :size) == previous, do: state, else: finish_owned(state)
  end

  defp observe(state) do
    owned = :ets.tab2list(state.table) |> Enum.map(&elem(&1, 0))
    processes = [state.caller | owned]

    infos =
      Enum.flat_map(processes, fn pid ->
        case Process.info(pid, [
               :memory,
               :total_heap_size,
               :binary,
               :reductions,
               :message_queue_len
             ]) do
          nil -> []
          info -> [{pid, info}]
        end
      end)

    reductions =
      Enum.reduce(infos, state.reductions, fn {pid, info}, acc ->
        Map.update(acc, pid, info[:reductions], &max(&1, info[:reductions]))
      end)

    infos = Enum.map(infos, &elem(&1, 1))
    binaries = infos |> Enum.flat_map(&Keyword.fetch!(&1, :binary))
    binary_sizes = Map.new(binaries, fn {id, bytes, _refs} -> {id, bytes} end)
    vm = :erlang.memory()

    values = %{
      process_memory_bytes: Enum.sum(Enum.map(infos, &Keyword.fetch!(&1, :memory))),
      process_heap_bytes:
        Enum.sum(Enum.map(infos, &Keyword.fetch!(&1, :total_heap_size))) *
          :erlang.system_info(:wordsize),
      shared_binary_bytes: binary_sizes |> Map.values() |> Enum.sum(),
      vm_total_bytes: vm[:total],
      vm_processes_bytes: vm[:processes],
      vm_binary_bytes: vm[:binary],
      live_owned: Enum.count(owned, &Process.alive?/1),
      mailbox_messages: Enum.sum(Enum.map(infos, &Keyword.fetch!(&1, :message_queue_len)))
    }

    peaks = Map.merge(state.observed_peak, values, fn _key, old, new -> max(old, new) end)
    %{state | observations: state.observations + 1, observed_peak: peaks, reductions: reductions}
  end

  defp isolated(fun, start \\ fn _pid -> :ok end) do
    parent = self()
    tag = make_ref()

    {pid, ref} =
      spawn_monitor(fn ->
        result =
          try do
            {:ok, fun.()}
          rescue
            error -> {:error, error, __STACKTRACE__}
          end

        send(parent, {tag, result})
      end)

    try do
      start.(pid)

      result =
        receive do
          {^tag, result} ->
            result

          {:DOWN, ^ref, :process, ^pid, reason} ->
            raise "benchmark process failed: #{inspect(reason)}"
        after
          120_000 -> raise "benchmark exceeded the safety limit"
        end

      receive do
        {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
      after
        @timeout -> raise "benchmark process did not stop"
      end

      case result do
        {:ok, value} -> value
        {:error, error, stacktrace} -> reraise error, stacktrace
      end
    after
      Process.exit(pid, :kill)
      Process.demonitor(ref, [:flush])
    end
  end
end
