defmodule Jido.Examples.Plugins.CommitProjection.AgentFacet do
  @moduledoc "Copies the domain count into one portable Plugin-owned field."
  use Jido.Agent.Plugin

  @impl true
  def state_spec(_opts), do: {:projection, Zoi.integer() |> Zoi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.state.count}
end

defmodule Jido.Examples.Plugins.CommitProjection.Runtime do
  @moduledoc "Keeps a live view of the Plugin's exact committed value and revision."
  use GenServer

  def start_link(init), do: GenServer.start_link(__MODULE__, init)
  def view(runtime), do: GenServer.call(runtime, :view)
  def update(runtime, commit), do: GenServer.call(runtime, {:update, commit})

  @impl true
  def init(init), do: {:ok, {init.plugin_state, init.state_version}}

  @impl true
  def handle_call(:view, _from, state), do: {:reply, state, state}

  def handle_call({:update, commit}, _from, _state),
    do: {:reply, :ok, {commit.plugin_state, commit.state_version}}
end

defmodule Jido.Examples.Plugins.CommitProjection.ServerFacet do
  @moduledoc "Updates the live view after each commit, without a custom Directive."
  use Jido.AgentServer.Plugin

  alias Jido.Examples.Plugins.CommitProjection.Runtime

  def child_spec(init), do: Supervisor.child_spec({Runtime, init}, [])

  @impl true
  def after_commit(runtime, commit, _opts), do: Runtime.update(runtime, commit)
end

defmodule Jido.Examples.Plugins.CommitProjection.Package do
  @moduledoc "Pairs pure state reduction with an optional live commit notification."
  use Jido.Plugin,
    agent: Jido.Examples.Plugins.CommitProjection.AgentFacet,
    agent_server: Jido.Examples.Plugins.CommitProjection.ServerFacet
end

defmodule Jido.Examples.Plugins.CommitProjection.Agent do
  @moduledoc "Changes domain state without knowing how the Plugin updates its runtime."
  use Jido.Agent, name: "plugin_commit_projection_agent"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    plugin Jido.Examples.Plugins.CommitProjection.Package
  end

  routes do
    signal_source "/examples/plugins/commit_projection"

    route "examples.plugins.commit_projection.add" do
      action %{amount: amount}, schema: Zoi.object(%{amount: Zoi.integer()}), context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end
  end
end
