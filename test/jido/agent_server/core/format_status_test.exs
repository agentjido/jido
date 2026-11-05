defmodule Jido.AgentServer.Core.FormatStatusTest do
  use Jido.Test.Case, async: false
  import ExUnit.CaptureLog
  alias Jido.AgentServer, as: Server
  alias Jido.Joi

  @sentinel "STATE-SENTINEL-7f3a"

  defmodule Holder do
    use Jido.Agent, name: "format_status_holder"

    state do
      schema Joi.object(%{secret: Joi.string() |> Joi.default("")})
    end

    routes do
      signal_source "/format-status"

      route "holder.noop", as: :noop do
        action _input, schema: Joi.object(%{}), context: context do
          {:ok, context.agent_state}
        end
      end
    end
  end

  defp start(c) do
    agent = Holder.instantiate!(id: unique_id("holder"), state: %{secret: @sentinel})
    assert {:ok, server} = Jido.start_agent(c.jido, agent)
    assert :ok = Server.await_ready(server)
    server
  end

  defp printed(term), do: inspect(term, limit: :infinity, printable_limit: :infinity)

  test ":sys.get_status omits Agent state", c do
    server = start(c)
    assert Server.agent(server).state.secret == @sentinel

    status = printed(:sys.get_status(server))

    refute status =~ @sentinel
    assert status =~ "agent_id"
  end

  test "a crash from an unexpected event logs no Agent state", c do
    server = start(c)
    ref = Process.monitor(server)

    log =
      capture_log(fn ->
        :gen_statem.cast(server, :unexpected_event)
        assert_receive {:DOWN, ^ref, _, _, _}, 2_000
        Process.sleep(50)
      end)

    assert log =~ "unexpected_event"
    refute log =~ @sentinel
  end

  test "format_status redacts every term a crash report prints" do
    secret = Holder.noop_signal!(%{}) |> Map.put(:data, %{secret: @sentinel})

    status =
      Server.format_status(%{
        state: :idle,
        data: %{agent: %{id: "a", module: Holder}, state_version: 3, secret: @sentinel},
        reason: %MatchError{term: @sentinel},
        queue: [{:cast, secret}],
        postponed: [{:cast, secret}],
        timeouts: [{:state_timeout, secret}],
        log: [{:in, secret}]
      })

    refute printed(status) =~ @sentinel
    assert status.state == :idle
    assert status.reason == MatchError
    assert status.data.state_version == 3
  end
end
