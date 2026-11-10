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

  test "a host delivers one cron occurrence Signal" do
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, Store)}
    jido = start_durable_jido(persistence)

    {:ok, request} =
      Jido.Signal.new("examples.durable.cron.request", %{report: "daily"}, source: "/examples/durable")

    assert {:ok, %Status{state: :waiting, waits: [%{id: wait_id}], ref: ref}} =
             Durable.start(jido, CronSignal, request, now: 1_000)

    {:ok, template} =
      Jido.Signal.new("examples.durable.cron.tick", %{report: "daily"}, source: "/examples/durable")

    scheduled_at = ~U[2026-11-10 12:00:00Z]

    assert {:ok, occurrence} =
             Scheduler.occurrence_signal(template, {jido, "reports"}, "daily", 1, scheduled_at)

    assert {:ok, %Occurrence{generation: 1, scheduled_at: "2026-11-10T12:00:00.000000Z"}} =
             Occurrence.from_signal(occurrence)

    assert :ok = Durable.signal(jido, ref, wait_id, occurrence, now: 2_000)
    assert {:ok, %Status{state: :completed}} = Durable.resume(jido, ref, now: 2_000)
    assert {:ok, %{report: "daily"}} = Durable.result(jido, ref)
  end

  defp start_durable_jido(persistence) do
    suffix = System.unique_integer([:positive])
    jido = :"cron_signal_durable_#{suffix}"

    start_supervised!(
      {Jido, name: jido, namespace: "examples/cron-signal/#{suffix}", persistence: persistence},
      id: jido
    )

    jido
  end
end
