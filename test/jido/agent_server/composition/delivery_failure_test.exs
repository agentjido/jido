defmodule Jido.AgentServer.Composition.DeliveryFailureTest do
  use Jido.Test.Case, async: true
  use Covenant.Case, component: "jido.agent_server.composition", async: true
  import ExUnit.CaptureLog
  import Jido.Test.Eventually
  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.Joi

  defmodule Leaf do
    use Jido.Agent, name: "delivery_failure_leaf"

    state do
      schema Joi.object(%{pings: Joi.integer() |> Joi.default(0)})
    end

    routes do
      signal_source "/delivery-failure"

      route "x.ping", as: :ping do
        action _input, schema: Joi.object(%{}), context: context do
          {:ok, %{context.agent_state | pings: context.agent_state.pings + 1}}
        end
      end
    end
  end

  defmodule Source do
    use Jido.Agent, name: "delivery_failure_source"

    routes do
      signal_source "/delivery-failure"

      route "a.go", as: :go do
        action _input, schema: Joi.object(%{}), context: context do
          {:ok, context.agent_state, [Directive.emit("x.ping", %{})]}
        end
      end
    end
  end

  defmodule Pipe do
    use Jido.Agent, name: "delivery_failure_pipe"

    topology do
      agent :a, Source
      agent :b, Leaf

      connections do
        connect "x.ping", from: :a, to: :b
      end
    end
  end

  defp start_pipe(c) do
    assert {:ok, owner} = Jido.start_agent(c.jido, Pipe, id: unique_id("pipe"))
    assert :ok = Server.await_ready(owner)
    owner
  end

  defp go, do: Source.go_signal!(%{})

  @tag obligation: "jido.agent_server.composition.I8"
  test "a member output with no live destination marks an effect failed and keeps the owner",
       c do
    owner = start_pipe(c)
    [source] = Server.members(owner, :a)
    assert :ok = Server.stop_child(owner, "$topology/b/1", :shutdown)
    assert [] = Server.members(owner, :b)

    log =
      capture_log(fn ->
        assert :ok = Server.cast(source, go())
        assert_eventually(match?(%{status: :failed}, Server.status(owner).last_effect_outcome), timeout: 5_000)
      end)

    assert log =~ "x.ping"
    assert log =~ "agent_not_found"
    assert Process.alive?(owner)
    assert [^source] = Server.members(owner, :a)

    assert %{turn_id: nil, status: :failed, stage: :directive} =
             Server.status(owner).last_effect_outcome
  end

  @tag obligation: "jido.agent_server.composition.I8"
  test "killing a destination member under traffic never stops the owner", c do
    for _run <- 1..25 do
      owner = start_pipe(c)
      owner_ref = Process.monitor(owner)
      [source] = Server.members(owner, :a)
      [destination] = Server.members(owner, :b)

      traffic =
        spawn(fn ->
          Stream.repeatedly(fn ->
            Server.cast(source, go())
            Process.sleep(1)
          end)
          |> Stream.run()
        end)

      Process.sleep(10)
      Process.exit(Server.activation(destination), :kill)
      refute_receive {:DOWN, ^owner_ref, _, _, _}, 100
      Process.exit(traffic, :kill)

      assert_eventually(match?([_], Server.members(owner, :b)), timeout: 5_000)
      [restarted] = Server.members(owner, :b)
      refute restarted == destination
      before = Server.agent(restarted).state.pings

      # A cast can be dropped while the source drains the traffic, so repeat it.
      assert_eventually(
        (
          Server.cast(source, go())
          Server.agent(restarted).state.pings > before
        ),
        timeout: 5_000
      )

      assert :ok = Jido.stop_agent(c.jido, owner)
    end
  end
end
