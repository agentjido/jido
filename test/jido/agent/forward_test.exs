defmodule Jido.Agent.ForwardTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.AgentServer
  alias Jido.Signal

  defmodule Increment do
    use Jido.Action, name: "forward_increment"

    @impl true
    def run(_input, context) do
      {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
    end
  end

  defmodule Worker do
    use Jido.Agent, name: "forward_worker"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "work.request", Increment
      forward "work.completed", to: parent()
    end
  end

  defmodule Parent do
    use Jido.Agent, name: "forward_parent"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      forward "work.request", to: agent(:worker)
      route "work.completed", Increment
    end

    topology do
      agent :worker, Worker
    end
  end

  test "forward destinations are portable canonical data" do
    assert [to_worker, to_parent] = [
             hd(Parent.definition().routes),
             List.last(Worker.definition().routes)
           ]

    assert to_worker.handler == %{
             kind: :forward,
             target: %{kind: :agent, name: :worker}
           }

    assert to_parent.handler == %{kind: :forward, target: %{kind: :parent}}
  end

  test "forward sends to one declared Agent without default dispatch fallback", %{jido: jido} do
    {:ok, parent} =
      JidoTest.AgentServerAssertions.start_agent(jido, Parent,
        default_dispatch: {:pid, target: self()}
      )

    [worker] = AgentServer.members(parent, :worker)
    signal = Signal.new!("work.request", %{}, source: "/test")

    assert {:ok, _, [%Jido.AgentServer.Directive.AgentSend{name: :worker}]} =
             AgentServer.call(parent, signal)

    eventually(fn -> AgentServer.agent(worker).state.count == 1 end)
    refute_received {:signal, _signal}
  end

  test "forward sends to the current parent Agent", %{jido: jido} do
    {:ok, parent} = JidoTest.AgentServerAssertions.start_agent(jido, Parent)
    [worker] = AgentServer.members(parent, :worker)
    signal = Signal.new!("work.completed", %{}, source: "/test")

    assert {:ok, _, [%Jido.AgentServer.Directive.ParentSend{}]} =
             AgentServer.call(worker, signal)

    eventually(fn -> AgentServer.agent(parent).state.count == 1 end)
  end

  test "forward rejects missing definition and runtime targets", %{jido: jido} do
    assert {:error, %Agent.Error{code: :unknown_forward_target}} =
             Agent.define(%{
               name: "missing_forward_target",
               routes: [
                 %{
                   path: "work.request",
                   handler: %{kind: :forward, target: %{kind: :agent, name: :missing}}
                 }
               ]
             })

    {:ok, worker} = JidoTest.AgentServerAssertions.start_agent(jido, Worker)
    signal = Signal.new!("work.completed", %{}, source: "/test")

    assert {:error, :parent_not_found} = AgentServer.call(worker, signal)
    assert AgentServer.status(worker).state_version == 0
  end
end
