defmodule Jido.AgentServer.Composition.SelfEmitTest do
  use Jido.Test.Case, async: true
  import ExUnit.CaptureLog
  import Jido.Test.Eventually
  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.Joi

  defmodule Looper do
    use Jido.Agent, name: "self_emit_looper"

    state do
      schema Joi.object(%{count: Joi.integer() |> Joi.default(0)})
    end

    routes do
      signal_source "/self-emit"

      route "loop.tick", as: :tick do
        action _input, schema: Joi.object(%{}), context: context do
          state = %{context.agent_state | count: context.agent_state.count + 1}
          {:ok, state, [Directive.emit("loop.tock", %{})]}
        end
      end

      route "loop.tock", as: :tock do
        action _input, schema: Joi.object(%{}), context: context do
          state = %{context.agent_state | count: context.agent_state.count + 1}
          {:ok, state, [Directive.emit("loop.tick", %{})]}
        end
      end

      route "loop.unrouted", as: :unrouted do
        action _input, schema: Joi.object(%{}), context: context do
          {:ok, context.agent_state, [Directive.emit("nobody.home", %{})]}
        end
      end
    end
  end

  defp start(c) do
    assert {:ok, server} = Jido.start_agent(c.jido, Looper, id: unique_id("looper"))
    assert :ok = Server.await_ready(server)
    server
  end

  test "a chain of untargeted Emits ends at the hop limit and names the type and reason", c do
    server = start(c)

    log =
      capture_log(fn ->
        assert {:ok, _, _} = Server.call(server, Looper.tick_signal!(%{}))

        assert_eventually(match?(%{status: :failed}, Server.status(server).last_effect_outcome))
      end)

    assert log =~ "AgentServer self emit refused"
    assert log =~ "self_emit_limit"
    assert log =~ ~r/signal type loop\.t(ick|ock)/

    assert Server.agent(server).state.count == 33
    Process.sleep(50)
    assert Server.agent(server).state.count == 33
    assert Process.alive?(server)
  end

  test "a later Signal starts a new chain after the limit", c do
    server = start(c)

    capture_log(fn ->
      assert {:ok, _, _} = Server.call(server, Looper.tick_signal!(%{}))
      assert_eventually(Server.agent(server).state.count == 33)
      assert {:ok, _, _} = Server.call(server, Looper.tick_signal!(%{}))
      assert_eventually(Server.agent(server).state.count == 66)
    end)
  end

  test "an unrouted untargeted Emit logs its type and reason", c do
    server = start(c)

    log =
      capture_log(fn ->
        assert {:ok, _, _} = Server.call(server, Looper.unrouted_signal!(%{}))
        assert_eventually(Server.status(server).last_outcome.status != :succeeded)
      end)

    assert log =~ "AgentServer cast turn failed: signal type nobody.home, reason :unmatched_input"
  end
end
