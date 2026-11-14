Code.require_file("signal_resume.ex", __DIR__)

defmodule Jido.Examples.Durability.SignalResumeTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  alias Jido.Durable
  alias Jido.Durable.Status
  alias Jido.Examples.Durability.SignalResume
  alias Jido.Plugin.Timer
  alias Jido.Plugin.Timer.Occurrence

  test "signal/5 resumes a wait with a host-created cron occurrence" do
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, Store)}
    jido = start_durable_jido(persistence)

    {:ok, request} =
      Jido.Signal.new("examples.durable.cron.request", %{report: "daily"}, source: "/examples/durable")

    assert {:ok, %Status{state: :waiting, waits: [%{id: wait_id}], ref: ref}} =
             Durable.start(jido, SignalResume, request, now: 1_000)

    {:ok, template} =
      Jido.Signal.new("examples.durable.cron.tick", %{report: "daily"}, source: "/examples/durable")

    scheduled_at = ~U[2026-11-10 12:00:00Z]

    assert {:ok, occurrence} =
             Timer.occurrence_signal(template, {jido, "reports"}, "daily", 1, scheduled_at)

    assert {:ok, %Occurrence{generation: 1}} = Occurrence.from_signal(occurrence)

    assert {:ok, %Status{state: :completed}} =
             Durable.signal(jido, ref, wait_id, occurrence, now: 2_000)

    assert {:ok, %{report: "daily"}} = Durable.result(jido, ref)
  end

  defp start_durable_jido(persistence) do
    suffix = System.unique_integer([:positive])
    jido = :"signal_resume_#{suffix}"

    start_supervised!(
      {Jido, name: jido, namespace: "examples/signal-resume/#{suffix}", persistence: persistence},
      id: jido
    )

    jido
  end
end
