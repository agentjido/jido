Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Durability.TimedResumeTest do
  use Jido.Test.Case, async: false
  @moduletag :example

  alias Jido.Durable
  alias Jido.Durable.Status
  alias Jido.Examples.Durability.TimedResume

  setup_all do
    Jido.Test.Examples.Loader.require_source!("05_flow_durability/05_04_timed_resume/timed_resume.ex")

    :ok
  end

  test "resume/3 releases a saved timer at its wake time" do
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, Store)}
    jido = start_durable_jido(persistence)

    {:ok, request} =
      Jido.Signal.new("examples.durable.timer.start", %{}, source: "/examples/durable")

    assert {:ok, %Status{state: :waiting, next_wake_at: 61_000, ref: ref}} =
             Durable.start(jido, TimedResume, request, now: 1_000)

    assert {:ok, %Status{state: :completed}} =
             Durable.resume(jido, ref, now: 61_000)

    assert {:ok, %{fired_at: 61_000}} = Durable.result(jido, ref)
  end

  defp start_durable_jido(persistence) do
    suffix = System.unique_integer([:positive])
    jido = :"timed_resume_#{suffix}"

    start_supervised!(
      {Jido, name: jido, namespace: "examples/timed-resume/#{suffix}", persistence: persistence},
      id: jido
    )

    jido
  end
end
