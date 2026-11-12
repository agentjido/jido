defmodule Jido.Agent.Plugin.FSMDurableTest do
  use Jido.Test.Case, async: false

  @moduletag :tmp_dir

  alias Jido.Agent.Plugin.FSM
  alias Jido.AgentServer, as: Server

  defmodule Approval do
    use Jido.Flow,
      name: "fsm_durable_approval",
      schema: Jido.Joi.object(%{request_id: Jido.Joi.string()})

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
      plugins: [{FSM, %{definition_vsn: 1}}]

    state do
      schema(
        Jido.Joi.object(%{
          status: Jido.Joi.enum([:idle, :approved, :expired]) |> Jido.Joi.default(:idle)
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
    instance = String.to_atom("fsm_durable_#{System.unique_integer([:positive])}")
    namespace = "jido/test/fsm-durable/#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido,
       name: instance,
       namespace: namespace,
       persistence: {Jido.Persistence.File, path: c.tmp_dir},
       activation: [idle_residency_timeout: 5_000]},
      id: instance
    )

    ref = Jido.Agent.Ref.new!(namespace: namespace, id: id)
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, Agent)

    request =
      Jido.Signal.new!("request", %{request_id: "one"}, source: "/plugin/fsm/durable")

    pending = Jido.submit(instance, ref, request)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :waiting, waits: [wait]}} =
             Server.await(pending)

    assert %Jido.AgentServer.Status{work_state: :waiting, waits: [^wait]} =
             Jido.status(instance, ref)

    assert {:ok, server} = Jido.resolve_agent(instance, ref)

    assert Server.snapshot(server).agent.state == %{
             status: :idle,
             fsm: %{definition_vsn: 1, current: :idle}
           }

    approval =
      Jido.Signal.new!("approved", %{request_id: "one"}, source: "/plugin/fsm/durable")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(instance, ref, approval)

    assert {:ok, server} = Jido.resolve_agent(instance, ref)
    completed = Server.snapshot(server).agent
    assert completed.state.status == :approved
    assert completed.state.fsm == %{definition_vsn: 1, current: :ready}
  end
end
