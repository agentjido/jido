defmodule Jido.Agent.FlowModesTest do
  use Jido.Test.Case, async: true

  alias Jido.AgentServer
  alias Jido.Persistence.ETS

  defmodule Add do
    use Jido.Action, name: "flow_mode_add"

    @impl true
    def run(%{amount: amount}, context) do
      {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
    end
  end

  defmodule Flow do
    use Jido.Flow,
      name: "flow_mode_contract",
      schema: Jido.Joi.object(%{amount: Jido.Joi.integer()})

    flow do
      step "add", action: Add, params: input()
      output result("add")
    end
  end

  defmodule Worker do
    use Jido.Agent, name: "flow_mode_worker"

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "work", Flow
    end
  end

  test "one Flow has the same result in direct, managed, and durable execution", %{jido: jido} do
    signal = Jido.Signal.new!("work", %{amount: 4}, source: "/flow-modes")
    direct_source = Worker.instantiate!(id: unique_id("direct"))

    assert {:ok, direct, direct_directives} = Jido.Agent.cmd(direct_source, signal)

    assert {:ok, managed_server} =
             Jido.start_agent(jido, Worker, id: unique_id("managed"), persistence: false)

    assert :ok = AgentServer.await_ready(managed_server)
    assert {:ok, managed, managed_directives} = AgentServer.call(managed_server, signal)

    assert {:ok, durable_server} =
             Jido.start_agent(jido, Worker,
               id: unique_id("durable"),
               persistence: {ETS, table: __MODULE__}
             )

    assert :ok = AgentServer.await_ready(durable_server)
    assert {:ok, durable, durable_directives} = AgentServer.call(durable_server, signal)

    assert direct.state == managed.state
    assert managed.state == durable.state
    assert direct_directives == managed_directives
    assert managed_directives == durable_directives
    assert direct.state == %{count: 4}
  end
end
