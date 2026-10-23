defmodule Jido.Examples.OrphanAdoption.Child do
  @moduledoc "A worker that can survive its owner's activation."
  use Jido.Agent, name: "multi_agent_orphan_adoption_child"

  state do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    route "examples.multi_agent.orphan_adoption.work" do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context,
        output_schema: Zoi.map() do
        {:ok, %{context.agent_state | total: context.agent_state.total + value}}
      end

      state(from: output())
    end
  end
end

defmodule Jido.Examples.OrphanAdoption.Parent do
  @moduledoc "Starts an independent worker and addresses it after adoption."
  use Jido.Agent, name: "multi_agent_orphan_adoption_parent"

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.OrphanAdoption.Child

  state do
    schema Zoi.object(%{forwarded: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/multi_agent/orphan_adoption"

    route "examples.multi_agent.orphan_adoption.forward", as: :forward do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context,
        output_schema: Zoi.map() do
        signal =
          Jido.Signal.new!("examples.multi_agent.orphan_adoption.work", %{value: value},
            source: "/examples/multi_agent/orphan_adoption"
          )

        {:ok, %{context.agent_state | forwarded: context.agent_state.forwarded + 1},
         [Jido.AgentServer.Directive.agent_send(:adopted, signal)]}
      end

      state(from: output())
    end
  end

  @doc "Starts a worker with an explicit lifetime policy and optional orphan destination."
  def start_worker(server, policy, opts \\ []) do
    child = Child.instantiate!(id: Server.agent(server).id <> "/worker")

    with {:ok, worker} <-
           Server.spawn_child(server, child, :worker,
             placement: :independent,
             on_parent_exit: policy,
             orphan_dispatch: opts[:orphan_dispatch]
           ),
         :ok <- Server.await_ready(worker),
         do: {:ok, worker}
  end
end
