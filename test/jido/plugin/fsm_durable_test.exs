defmodule Jido.Plugin.FSMDurableTest do
  use JidoTest.Case, async: false

  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.FSM

  defmodule Approval do
    use Jido.Flow,
      name: "fsm_durable_approval",
      schema: Zoi.object(%{request_id: Zoi.string()})

    flow do
      selection "decision" do
        await("approved", event: "approved", match: %{request_id: input(:request_id)})
        timer("expired", after_ms: 3_600_000)
      end

      step "finish", decision <- result("decision"), inline: [context: context] do
        status = if decision.selected == "approved", do: :approved, else: :expired
        {:ok, %{context.agent_state | status: status}}
      end

      output result("finish")
    end
  end

  defmodule Agent do
    use Jido.Agent,
      name: "fsm_durable_agent",
      extensions: [FSM]

    state do
      schema(
        Zoi.object(%{
          status: Zoi.enum([:idle, :approved, :expired]) |> Zoi.default(:idle)
        })
      )
    end

    state_machine do
      initial :idle
      terminal(:ready)
      transition(:approve, from: :idle, route: :approve, to: :ready)
    end

    routes do
      signal_source "/plugin/fsm/durable"
      route "request", Approval, as: :approve
    end
  end

  test "a durable Flow wait keeps the source FSM state until completion", c do
    id = unique_id("fsm-wait")
    persistence = {Jido.Persistence.File, path: c.tmp_dir}

    assert {:ok, server} =
             Jido.start_agent(c.jido, Agent, id: id, persistence: persistence)

    assert :ok = Server.await_ready(server)

    request =
      Jido.Signal.new!("request", %{request_id: "one"}, source: "/plugin/fsm/durable")

    pending = Server.submit(server, request)

    wait =
      eventually(fn ->
        case Server.status(server) do
          %{active: %{stage: :waiting}, waits: [wait]} -> wait
          _status -> nil
        end
      end)

    assert Server.agent(server).state == %{
             status: :idle,
             fsm: %{version: 1, current: :idle}
           }

    approval =
      Jido.Signal.new!("approved", %{request_id: "one"}, source: "/plugin/fsm/durable")

    assert :ok = Server.deliver_wait(server, wait.id, approval)

    assert {:ok, completed, []} = Server.await(pending)
    assert completed.state.status == :approved
    assert completed.state.fsm == %{version: 1, current: :ready}
  end
end
