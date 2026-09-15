defmodule JidoTest.System.Observability do
  @moduledoc false
  import ExUnit.Assertions

  @prefixes [
    [:jido, :agent, :turn],
    [:jido, :agent, :lifecycle],
    [:jido, :agent, :commit],
    [:jido, :agent, :after_commit],
    [:jido, :agent, :directive],
    [:jido, :persistence, :operation],
    [:jido, :topology, :operation]
  ]
  @points [
    [:jido, :agent, :admission, :rejected],
    [:jido, :agent, :turn, :settled],
    [:jido, :topology, :ownership, :settled]
  ]

  def start!(namespace, on_exit, context) do
    owner = self()

    {:ok, recorder} =
      Agent.start(fn ->
        %{
          owner: owner,
          events: [],
          logs: [],
          killed: MapSet.new(),
          effect_attempts: 0,
          measurements: %{},
          effect_ids: MapSet.new()
        }
      end)

    handler = {__MODULE__, make_ref()}
    logger = :"system_logs_#{System.unique_integer([:positive])}"

    :ok = :logger.add_handler(logger, __MODULE__, %{config: {recorder, Process.group_leader()}})

    events =
      for prefix <- @prefixes, ending <- [:start, :stop, :exception], do: prefix ++ [ending]

    :ok =
      :telemetry.attach_many(
        handler,
        events ++ @points,
        &__MODULE__.record/4,
        {recorder, namespace}
      )

    on_exit.(fn ->
      attached? = Enum.any?(:telemetry.list_handlers([]), &(&1.id == handler))
      logger_attached? = match?({:ok, _}, :logger.get_handler_config(logger))
      :logger.remove_handler(logger)
      :telemetry.detach(handler)
      evidence = Agent.get(recorder, & &1)
      Agent.stop(recorder)
      JidoTest.System.Report.save(context, evidence)
      assert attached?, "the system telemetry recorder detached before scenario cleanup"
      assert logger_attached?, "the system log recorder detached before scenario cleanup"
      assert_balanced(evidence)
    end)

    recorder
  end

  def record(event, measurements, metadata, {recorder, namespace}) do
    if metadata[:agent_namespace] == namespace or metadata[:topology_id] == namespace do
      entry = {self(), event, measurements, metadata}
      append(recorder, :events, entry)
    end
  end

  # Logger handlers run in the emitting process. System.Case installs a private
  # group leader, which supervised runtime children and Tasks retain.
  def log(%{meta: %{gl: leader}} = event, %{config: {recorder, leader}}),
    do: append(recorder, :logs, event)

  def log(_event, _config), do: :ok

  def service_log(recorder, service, message, metadata \\ %{}) do
    append(recorder, :logs, %{
      level: :info,
      msg: {:string, message},
      meta:
        Map.merge(Map.new(metadata), %{service: service, pid: self(), gl: Process.group_leader()})
    })
  end

  defp append(recorder, kind, entry) do
    Agent.update(recorder, fn state ->
      send(state.owner, {:system_observed, recorder, kind, entry})
      Map.update!(state, kind, &[entry | &1])
    end)
  end

  def logs(recorder), do: Agent.get(recorder, &Enum.reverse(&1.logs))

  def await(recorder, predicate, timeout \\ 10_000),
    do: await_entry(recorder, :events, events(recorder), predicate, timeout)

  def await_log(recorder, predicate, timeout \\ 10_000),
    do: await_entry(recorder, :logs, logs(recorder), predicate, timeout)

  defp await_entry(recorder, kind, history, predicate, timeout) do
    case Enum.find(history, predicate) do
      nil ->
        await_message(recorder, kind, predicate, System.monotonic_time(:millisecond) + timeout)

      entry ->
        entry
    end
  end

  defp await_message(recorder, kind, predicate, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:system_observed, ^recorder, ^kind, entry} ->
        if predicate.(entry), do: entry, else: await_message(recorder, kind, predicate, deadline)
    after
      remaining -> flunk("Missing system #{kind} event. Recent logs:\n#{format_logs(recorder)}")
    end
  end

  def format_logs(recorder) do
    recorder
    |> logs()
    |> Enum.take(-10)
    |> Enum.map_join(
      "\n",
      &(&1 |> :logger_formatter.format(%{}) |> IO.iodata_to_binary() |> String.slice(0, 1_000))
    )
  end

  def await_turn(recorder, server, version) do
    await(recorder, fn
      {^server, [:jido, :agent, :turn, :stop], %{state_version_after: ^version},
       %{status: :ok, committed?: true}} ->
        true

      _ ->
        false
    end)
  end

  def killed(recorder, pid),
    do: Agent.update(recorder, &Map.update!(&1, :killed, fn pids -> MapSet.put(pids, pid) end))

  def events(recorder), do: Agent.get(recorder, &Enum.reverse(&1.events))

  def effect_attempt(recorder, effect_id) do
    Agent.update(recorder, fn state ->
      %{
        state
        | effect_attempts: state.effect_attempts + 1,
          effect_ids: MapSet.put(state.effect_ids, effect_id)
      }
    end)
  end

  def measure(recorder, values) when is_map(values) and map_size(values) <= 32 do
    assert Enum.all?(values, fn {key, value} ->
             is_atom(key) and is_number(value) and value >= 0
           end)

    Agent.update(recorder, &%{&1 | measurements: Map.merge(&1.measurements, values)})
  end

  def assert_turn(recorder, signal, status, committed?, agent_id \\ nil) do
    entries =
      for {_, [:jido, :agent, :turn, ending], measurements, metadata} <- events(recorder),
          ending in [:start, :stop, :exception],
          metadata[:source_signal_id] == signal.id,
          is_nil(agent_id) or metadata[:agent_id] == agent_id,
          do: {ending, measurements, metadata}

    assert [{:start, _, start}, {:stop, measurements, stop}] = entries
    assert is_binary(start.turn_id)
    assert start.activation_id == stop.activation_id
    assert start.turn_id == stop.turn_id
    assert start.stage == :evaluate
    assert stop.status == status
    assert stop.committed? == committed?
    assert measurements.duration >= 0

    spans =
      for {_, [:jido, :agent, :commit, ending], _, metadata} <- events(recorder),
          metadata[:turn_id] == start.turn_id,
          do: ending

    assert spans == [:start, :stop],
           "missing or duplicate commit span for #{start.turn_id}"
  end

  def assert_topology(recorder, operation, count) do
    matches =
      for {_, [:jido, :topology, :operation, :stop], measurements, metadata} <- events(recorder),
          metadata.topology_operation == operation,
          do: {measurements, metadata}

    assert matches != []
    {measurements, metadata} = List.last(matches)
    assert metadata.status == :ok
    assert measurements.component_count == count
    assert measurements.ready_count == count
    assert measurements.failed_count == 0
  end

  def assert_persistence(recorder, status) do
    assert Enum.any?(events(recorder), fn
             {_, [:jido, :persistence, :operation, :stop], _, metadata} ->
               metadata.status == status

             _ ->
               false
           end)
  end

  defp assert_balanced(%{events: events, killed: killed}) do
    assert events != [], "the system scenario emitted no observed semantic events"

    for prefix <- [
          [:jido, :agent, :turn],
          [:jido, :agent, :lifecycle],
          [:jido, :agent, :commit],
          [:jido, :persistence, :operation]
        ] do
      assert Enum.any?(events, fn {_, event, _, _} -> event == prefix ++ [:start] end),
             "missing required semantic boundary: #{inspect(prefix)}"
    end

    pending =
      events
      |> Enum.reverse()
      |> Enum.reduce(%{}, fn {pid, event, measurements, metadata}, pending ->
        assert metadata.schema_version == 1
        assert Map.drop(metadata, [:state, :data, :signal, :raw_error, :context]) == metadata

        assert Enum.all?(metadata, fn
                 {_key, value} when is_binary(value) ->
                   byte_size(value) <= 256 and String.valid?(value)

                 {_key, value} ->
                   is_atom(value) or is_integer(value)
               end)

        assert Enum.all?(measurements, fn
                 {key, value} when key in [:system_time, :monotonic_time] -> is_integer(value)
                 {_key, value} -> is_integer(value) and value >= 0
               end)

        {ending, prefix} = List.pop_at(event, -1)

        key =
          {pid, prefix, metadata[:turn_id], metadata[:operation], metadata[:topology_operation]}

        case ending do
          point when point in [:rejected, :settled] ->
            pending

          :start ->
            assert Map.get(pending, key, 0) == 0,
                   "overlapping or duplicate span start: #{inspect(key)}"

            Map.put(pending, key, 1)

          terminal when terminal in [:stop, :exception] ->
            assert Map.get(pending, key, 0) > 0,
                   "unmatched or duplicate terminal: #{inspect(event)}"

            assert measurements.duration >= 0

            assert metadata[:status] in [
                     :ok,
                     :error,
                     :cancelled,
                     :timed_out,
                     :conflict,
                     :indeterminate,
                     :not_found,
                     :rejected
                   ]

            Map.update!(pending, key, &(&1 - 1))
        end
      end)

    for {{pid, prefix, _turn, _operation, _topology}, count} <- pending, count != 0 do
      # A hard kill cannot execute a terminal callback. It must be tied to the
      # exact monitored fault, never silently treated as a completed span.
      assert MapSet.member?(killed, pid),
             "missing terminal for #{inspect(prefix)} from #{inspect(pid)}"

      refute Process.alive?(pid)
    end
  end
end
