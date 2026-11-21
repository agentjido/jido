Code.require_file("example.ex", __DIR__)

defmodule Jido.Examples.Statechart.ReleaseTest do
  use Jido.Test.Case, async: false

  alias Jido.{AgentServer, Signal, Statechart}
  alias Jido.Examples.Statechart.Release

  @moduletag :integration

  test "a guard controls approval and a separate route records notes", %{jido: jido} do
    assert {:ok, agent} = Jido.start_agent(jido, Release, id: unique_id("release"))
    assert {:ok, %{status: :committed}} = Statechart.initialize(agent)

    assert {:ok, %{status: :committed}} = AgentServer.call(agent, event_signal("reviewed", %{"checks_passed" => false}))
    assert %{state: "review", status: :active} = Statechart.session(agent)

    assert {:ok, %{status: :committed}} = AgentServer.call(agent, event_signal("note", %{}))
    assert AgentServer.snapshot(agent).agent.state.notes == 1
    assert %{state: "review", status: :active} = Statechart.session(agent)

    assert {:ok, %{status: :committed}} = AgentServer.call(agent, event_signal("reviewed", %{"checks_passed" => true}))
    assert %{state: "approved", status: :completed} = Statechart.session(agent)

    assert :ok = Jido.stop_agent(jido, agent)
    refute Process.alive?(agent)
  end

  defp event_signal(event, data),
    do: Signal.new!("examples.statechart.release.#{event}", data, source: "/examples/statechart/release")
end
