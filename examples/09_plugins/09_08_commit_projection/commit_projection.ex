defmodule Jido.Examples.Plugins.CommitProjection.Agent do
  @moduledoc "Changes domain state without knowing how the Plugin updates its runtime."
  use Jido.Agent, name: "plugin_commit_projection_agent"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    plugin Jido.Examples.Plugins.CommitProjection.Package
  end

  routes do
    signal_source "/examples/plugins/commit_projection"

    route "examples.plugins.commit_projection.add", as: :add do
      action %{amount: amount}, schema: Zoi.object(%{amount: Zoi.integer()}), context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end
  end
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

defmodule Jido.Examples.Plugins.CommitProjection.Package do
  @moduledoc "Reduces owned state and requires its live view to update after commit."
  use Jido.Plugin

  alias Jido.Examples.Plugins.CommitProjection.Runtime

  @impl true
  def state_spec(_opts), do: {:projection, Zoi.integer() |> Zoi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.state.count}

  @impl true
  def child_spec(init), do: Supervisor.child_spec({Runtime, init}, [])

  @impl true
  def after_commit(runtime, commit, _opts), do: Runtime.update(runtime, commit)
end
