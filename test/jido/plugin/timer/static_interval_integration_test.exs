defmodule Jido.Plugin.Timer.StaticIntervalIntegrationTest do
  use Jido.Test.Case, async: false

  alias Jido.AgentServer
  alias Jido.Plugin.Timer

  defmodule RecordTick do
    use Jido.Action, name: "plugin_timer_record_static_tick"

    @impl Jido.Action
    def run(params, context) do
      {:ok, %{context.agent_state | ticks: context.agent_state.ticks ++ [params]}}
    end
  end

  defmodule Agent do
    use Jido.Agent,
      name: "plugin_timer_static_interval_agent",
      plugins: [
        {Timer,
         %{
           interval: 10,
           signal_type: "plugin.timer.tick",
           signal_data: %{source: :timer},
           source: "/test/timer"
         }}
      ]

    state do
      schema Jido.Joi.object(%{ticks: Jido.Joi.list(Jido.Joi.any()) |> Jido.Joi.default([])})
    end

    routes do
      route "plugin.timer.tick", RecordTick
    end
  end

  @tag obligation: "jido.plugin.timer.I10"
  test "a static interval starts automatically through the Timer runtime", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(jido, Agent, id: unique_id("static-timer"))

    eventually(fn ->
      case AgentServer.snapshot(server).agent.state.ticks do
        [%{source: :timer} | _rest] -> true
        _ticks -> false
      end
    end)

    assert %{pid: runtime} = Jido.Test.AgentServer.Assertions.plugin(server, Timer)
    assert is_pid(runtime)

    definition = AgentServer.snapshot(server).agent.state.timer.every.heartbeat
    assert definition.status == :running
    assert definition.interval_ms == 10
  end
end
