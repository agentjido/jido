Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Durability.CronSignalTest do
  use Jido.Test.Case, async: false
  @moduletag :example

  alias Jido.Durable
  alias Jido.Durable.Status
  alias Jido.Examples.Durability.CronSignal
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.Occurrence

  setup_all do
    Jido.Test.Examples.Loader.require_source!("05_flow_durability/05_07_cron_signal/cron_signal.ex")
    :ok
  end

  test "a host delivers one cron occurrence Signal", c do
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, Store)}

    {:ok, request} =
      Jido.Signal.new("examples.durable.cron.request", %{report: "daily"}, source: "/examples/durable")

    assert {:ok, %Status{state: :waiting, waits: [%{id: wait_id}], ref: ref}} =
             Durable.start(c.jido, CronSignal, request, persistence: persistence, now: 1_000)

    {:ok, template} =
      Jido.Signal.new("examples.durable.cron.tick", %{report: "daily"}, source: "/examples/durable")

    scheduled_at = ~U[2026-11-10 12:00:00Z]

    assert {:ok, occurrence} =
             Scheduler.occurrence_signal(template, {c.jido, "reports"}, "daily", 1, scheduled_at)

    assert {:ok, %Occurrence{generation: 1, scheduled_at: "2026-11-10T12:00:00.000000Z"}} =
             Occurrence.from_signal(occurrence)

    assert :ok = Durable.signal(c.jido, ref, wait_id, occurrence, persistence: persistence, now: 2_000)
    assert {:ok, %Status{state: :completed}} = Durable.resume(c.jido, ref, persistence: persistence, now: 2_000)
    assert {:ok, %{report: "daily"}} = Durable.result(c.jido, ref, persistence: persistence)
  end
end
