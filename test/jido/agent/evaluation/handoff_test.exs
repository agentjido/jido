defmodule Jido.Agent.Evaluation.HandoffTest do
  use Jido.Test.Case, async: true

  alias Jido.{Agent, AgentServer, Exec, Instruction, Persistence}
  alias Jido.Agent.Address
  alias Jido.AgentServer.TurnResult
  alias Jido.Durable.Continuation

  defmodule Successor do
    use Jido.Flow, name: "agent_raw_handoff_successor"

    def on_before_validate_params("bound payload"), do: {:ok, %{value: "validated payload"}}
    def on_before_validate_params(params), do: {:error, {:expected_raw_input, params}}

    flow do
      step "echo", value <- input(:value) do
        {:ok, %{value: value}}
      end

      output result("echo")
    end
  end

  defmodule SelectSuccessor do
    use Jido.Action, name: "agent_raw_handoff_selector"

    def run(_input, _context) do
      template = Instruction.template(:flow, Successor)
      {:ok, instruction} = Instruction.bind(template, "bound payload", %{})
      {:handoff, %{}, instruction}
    end
  end

  defmodule Predecessor do
    use Jido.Flow, name: "agent_raw_handoff_predecessor"

    flow do
      handoff "next", selector: SelectSuccessor, params: input()
      output result("next")
    end
  end

  defmodule Host do
    use Jido.Agent, name: "agent_raw_handoff"

    state do
      schema Jido.Joi.object(%{value: Jido.Joi.string() |> Jido.Joi.default("initial")})
    end

    routes do
      route "test.handoff", Predecessor, defaults: %{value: "route default"}
    end
  end

  test "a live Handoff runs the successor with its raw bound input", %{jido: jido} do
    agent = Host.instantiate!(id: "live-handoff")
    source = signal("test.handoff", %{value: "original Signal"})

    assert {:handoff, ^agent, %Instruction{params: "bound payload"} = successor, []} = Agent.cmd(agent, source)
    assert {:ok, %{value: "validated payload"}} = Exec.run(successor)

    assert {:ok, server} = Jido.start_agent(jido, agent)
    assert {:ok, %TurnResult{status: :committed, agent_revision: 2}} = AgentServer.call(server, source)
    assert AgentServer.snapshot(server).agent.state == %{value: "validated payload"}
  end

  @tag :tmp_dir
  test "a released durable Handoff restores the same raw bound Instruction", %{tmp_dir: path} = context do
    %{jido: jido} = restart_jido!(context, {Persistence.File, path: path})
    namespace = Jido.Instance.NamespaceRegistry.namespace(jido)
    address = Address.new!(namespace: namespace, id: "durable-handoff")
    source = signal("test.handoff", %{value: "original Signal"})
    agent = Host.instantiate!(id: address.id)

    assert {:ok, ^address} = Jido.create_agent(jido, address, Host)
    assert {:handoff, ^agent, %Instruction{params: "bound payload"} = successor, []} = Agent.cmd(agent, source)

    assert {:ok, accepted} =
             Continuation.accept_handoff(%{
               id: "restored-successor",
               signal: source,
               instruction: successor,
               context: %{},
               chain_id: "handoff-chain",
               chain_order: 1,
               predecessor_id: "committed-predecessor"
             })

    assert {:ok, released} =
             Continuation.release_handoff(accepted, %{
               admitted_signal: source,
               plugin_inputs: %{},
               expires_at: :infinity
             })

    assert :ok =
             Persistence.save_agent(jido, agent,
               revision: 1,
               expected_revision: 0,
               agent_revision: 1,
               server_turn: released
             )

    assert {:ok, ^agent, 1, 1, ^released} = Persistence.load_agent_address(jido, address)
    assert {:ok, server} = Jido.activate_agent(jido, address)

    assert eventually(fn -> match?(%{agent_revision: 2}, AgentServer.status(server)) end,
             timeout: 10_000,
             interval: 25
           )

    assert {:ok, %{state: %{value: "validated payload"}}, _revision, 2,
            %{id: "restored-successor", status: :completed, instruction: ^successor}} =
             Persistence.load_agent_address(jido, address)
  end
end
