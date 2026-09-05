defmodule JidoTest.Plugin.SchedulerOccurrenceTest do
  use ExUnit.Case, async: true
  @moduletag capability: "REC-03"

  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.Occurrence
  alias Jido.Signal

  @scope {ExampleJido, "agent-1", "tenant-1"}
  @instant ~U[2030-01-01 00:00:01Z]

  test "the same coordinates produce one ID across different Signal deliveries" do
    first = tick()
    second = tick()
    assert first.id != second.id
    assert {:ok, first} = Occurrence.attach(first, @scope, "job-1", 1, @instant)
    assert {:ok, second} = Occurrence.attach(second, @scope, "job-1", 1, @instant)
    assert {:ok, %Occurrence{} = occurrence} = Scheduler.occurrence(first)
    assert {:ok, ^occurrence} = Scheduler.occurrence(second)
  end

  test "instance, Agent, partition, job, generation, and UTC time distinguish IDs" do
    coordinates = [
      {@scope, "job-1", 1, @instant},
      {{AnotherJido, "agent-1", "tenant-1"}, "job-1", 1, @instant},
      {{ExampleJido, "agent-2", "tenant-1"}, "job-1", 1, @instant},
      {{ExampleJido, "agent-1", "tenant-2"}, "job-1", 1, @instant},
      {@scope, "job-2", 1, @instant},
      {@scope, "job-1", 2, @instant},
      {@scope, "job-1", 1, DateTime.add(@instant, 1, :second)}
    ]

    ids =
      Enum.map(coordinates, fn {scope, job, generation, instant} ->
        {:ok, signal} = Occurrence.attach(tick(), scope, job, generation, instant)
        {:ok, occurrence} = Scheduler.occurrence(signal)
        occurrence.id
      end)

    assert length(Enum.uniq(ids)) == length(coordinates)
  end

  test "UTC normalization equates offset representations and distinguishes repeated local times" do
    first_local = %{
      @instant
      | hour: 1,
        utc_offset: 3_600,
        zone_abbr: "TEST",
        time_zone: "Test/Zone"
    }

    second_local = %{first_local | utc_offset: 0}
    {:ok, utc} = Occurrence.attach(tick(), @scope, "job-1", 1, @instant)
    {:ok, first} = Occurrence.attach(tick(), @scope, "job-1", 1, first_local)
    {:ok, second} = Occurrence.attach(tick(), @scope, "job-1", 1, second_local)
    assert {:ok, %Occurrence{} = occurrence} = Scheduler.occurrence(utc)
    assert {:ok, ^occurrence} = Scheduler.occurrence(first)
    assert {:ok, %Occurrence{}} = Scheduler.occurrence(second)
    refute Scheduler.occurrence(first) == Scheduler.occurrence(second)
  end

  test "metadata preserves Signal data and context through the wire format" do
    signal = tick()
    {:ok, signal} = Signal.put_context(signal, "customer", "acme")

    {:ok, signal} =
      Signal.put_context(
        signal,
        "traceparent",
        "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
      )

    {:ok, tagged} = Occurrence.attach(signal, @scope, "job-1", 0, @instant)
    assert tagged.data == signal.data
    assert tagged.id == signal.id
    assert Signal.get_context(tagged, "customer") == "acme"
    assert Signal.get_context(tagged, "traceparent") == Signal.get_context(signal, "traceparent")
    assert {:ok, restored} = tagged |> Signal.to_map() |> Signal.new()
    assert {:ok, %Occurrence{} = occurrence} = Scheduler.occurrence(tagged)
    assert {:ok, ^occurrence} = Scheduler.occurrence(restored)
  end

  test "missing and malformed occurrence metadata return tagged errors" do
    assert {:error, :not_found} = Scheduler.occurrence(tick())
    {:ok, partial} = Signal.put_context(tick(), "jidooccurrenceid", "occ_partial")
    assert {:error, _} = Scheduler.occurrence(partial)
    {:ok, tagged} = Occurrence.attach(tick(), @scope, "job-1", 1, @instant)

    for {key, value} <- [
          {"jidoschedulegen", -1},
          {"jidoschedulegen", "1"},
          {"jidoscheduledat", "not a timestamp"},
          {"jidoscheduledat", "2030-01-01T01:00:01+01:00"}
        ] do
      {:ok, invalid} = Signal.put_context(tagged, key, value)
      assert {:error, _} = Scheduler.occurrence(invalid)
    end
  end

  test "plain cron definitions retain their prior checkpoint shape" do
    signal = tick()

    assert {:ok, directive} =
             Scheduler.validate_directive(Scheduler.cron(:plain, "* * * * *", signal), [])

    assert {:ok, %{cron: %{plain: spec}}} = Scheduler.update_state(%{cron: %{}}, [directive], [])
    assert spec == %{cron_expression: "* * * * *", message: signal, timezone: "Etc/UTC"}
    assert :ok = Scheduler.validate_cron_state(%{plain: spec}, [])
  end

  test "delayed schedule construction keeps invalid values for later validation" do
    signal = tick()
    assert Scheduler.schedule(10, signal) == %Scheduler.Schedule{delay_ms: 10, signal: signal}
    invalid = Scheduler.schedule(-1, :not_a_signal)
    assert invalid == %Scheduler.Schedule{delay_ms: -1, signal: :not_a_signal}
    assert {:error, _} = Scheduler.validate_directive(invalid, [])
  end

  test "timezone defaults are shared by validation and stored definitions" do
    for timezone <- [nil, "", "Etc/UTC"] do
      assert {:ok, directive} =
               Scheduler.validate_directive(
                 Scheduler.cron(:plain, "* * * * *", tick(), timezone: timezone),
                 []
               )

      assert directive.timezone == "Etc/UTC"
      assert Scheduler.build_cron_spec("* * * * *", tick(), timezone).timezone == "Etc/UTC"
    end
  end

  test "cron state validation preserves the first error when several fields are invalid" do
    invalid_message = %{tick() | data: %{pid: self()}}

    for {cron, message, timezone, reason} <- [
          {nil, invalid_message, 123, {:invalid_cron, :invalid_type}},
          {"bad cron", invalid_message, 123, {:invalid_timezone, :invalid_type}},
          {"bad cron", invalid_message, "Not/AZone", {:invalid_message, :non_durable_term}}
        ] do
      assert {:error, error} =
               Scheduler.validate_cron_state(
                 %{job: %{cron_expression: cron, message: message, timezone: timezone}},
                 []
               )

      assert error == "invalid cron state for :job: #{inspect(reason)}"
    end

    assert {:error, syntax_error} =
             Scheduler.validate_directive(
               Scheduler.cron(:job, "bad cron", tick(), timezone: "Not/AZone"),
               []
             )

    assert {:invalid_cron, _} = syntax_error

    assert {:error, {:invalid_timezone, _}} =
             Scheduler.validate_directive(
               Scheduler.cron(:job, "* * * * *", tick(), timezone: "Not/AZone"),
               []
             )
  end

  test "tracked schedules reject reserved template metadata" do
    {:ok, tagged} = Occurrence.attach(tick(), @scope, "job-1", 1, @instant)

    assert {:error, :reserved_occurrence_metadata} =
             Scheduler.validate_directive(
               Scheduler.cron("job-1", "* * * * *", tagged, generation: 1),
               []
             )

    spec = Scheduler.build_cron_spec("* * * * *", tagged, nil, 1)
    assert {:error, _} = Scheduler.validate_cron_state(%{"job-1" => spec}, [])
  end

  defp tick, do: Signal.new!("test.tick", %{value: 7}, source: "/test")
end
