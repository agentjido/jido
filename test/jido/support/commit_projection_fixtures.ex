defmodule JidoTest.CommitProjection.Effect do
  @moduledoc false
  use Jido.Agent.Directive
  defstruct [:sink]
end

defmodule JidoTest.CommitProjection.AgentFacet do
  @moduledoc false
  use Jido.Agent.Plugin

  def state_spec(opts), do: {Keyword.fetch!(opts, :key), Zoi.integer() |> Zoi.default(0)}

  def directives(opts),
    do: if(opts[:key] == :first, do: [JidoTest.CommitProjection.Effect], else: [])

  def reduce(reduction, _opts), do: {:ok, reduction.state.count}
end

defmodule JidoTest.CommitProjection.ServerFacet do
  @moduledoc false
  use Jido.AgentServer.Plugin

  def after_commit(runtime, commit, opts) do
    sink = Keyword.fetch!(opts, :sink)
    Agent.update(sink, &(&1 ++ [{:commit, commit.plugin, runtime, commit}]))
    if observer = opts[:observer], do: send(observer, {:commit_started, commit, self()})

    if gate = opts[:gate] do
      receive do
        {:release, ^gate} -> :ok
      end
    end

    case opts[:result] do
      nil ->
        :ok

      :error ->
        {:error, :projection_unavailable}

      :raise ->
        raise "private projection error"

      :throw ->
        throw(:projection_failed)

      :exit ->
        exit(:projection_failed)

      :kill ->
        Process.exit(self(), :kill)

      :invalid ->
        {:ok, %{count: 999}, []}

      :reentrant ->
        server = Jido.whereis_agent(commit.jido, commit.agent_id)

        result =
          Jido.AgentServer.call(server, JidoTest.Case.signal("projection.update", %{amount: 1}))

        send(opts[:observer], {:reentrant_result, result})
        :ok
    end
  end

  def dispatch(_runtime, %{sink: sink}, _context, _opts) do
    Agent.update(sink, &(&1 ++ [:effect]))
  end
end

defmodule JidoTest.CommitProjection.First do
  @moduledoc false
  use Jido.Plugin,
    agent: JidoTest.CommitProjection.AgentFacet,
    agent_server: JidoTest.CommitProjection.ServerFacet
end

defmodule JidoTest.CommitProjection.Second do
  @moduledoc false
  use Jido.Plugin,
    agent: JidoTest.CommitProjection.AgentFacet,
    agent_server: JidoTest.CommitProjection.NotificationFacet
end

defmodule JidoTest.CommitProjection.NotificationFacet do
  @moduledoc false
  use Jido.AgentServer.Plugin
  defdelegate after_commit(runtime, commit, opts), to: JidoTest.CommitProjection.ServerFacet
end

defmodule JidoTest.CommitProjection.Stateless do
  @moduledoc false
  use Jido.Plugin, agent_server: JidoTest.CommitProjection.NotificationFacet
end

defmodule JidoTest.CommitProjection.Runtime do
  @moduledoc false
  use GenServer

  def start_link(init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(init) do
    send(init.options[:observer], {:projection_init, self(), init})
    {:ok, {init.plugin_state, init.state_version}}
  end

  @impl true
  def handle_call({:commit, commit}, _from, _state) do
    {:reply, :ok, {commit.plugin_state, commit.state_version}}
  end

  def handle_call(:view, _from, state), do: {:reply, state, state}
end

defmodule JidoTest.CommitProjection.RuntimeFacet do
  @moduledoc false
  use Jido.AgentServer.Plugin

  def child_spec(init), do: Supervisor.child_spec({JidoTest.CommitProjection.Runtime, init}, [])
  def after_commit(runtime, commit, _opts), do: GenServer.call(runtime, {:commit, commit})
end

defmodule JidoTest.CommitProjection.Projection do
  @moduledoc false
  use Jido.Plugin,
    agent: JidoTest.CommitProjection.AgentFacet,
    agent_server: JidoTest.CommitProjection.RuntimeFacet
end

defmodule JidoTest.CommitProjection.Update do
  @moduledoc false
  use Jido.Action,
    name: "commit_projection_update",
    schema:
      Zoi.object(%{amount: Zoi.integer(), directives: Zoi.list(Zoi.any()) |> Zoi.default([])})

  def run(params, context) do
    {:ok, %{context.agent_state | count: context.agent_state.count + params.amount},
     params.directives}
  end
end

defmodule JidoTest.CommitProjection.Reject do
  @moduledoc false
  use Jido.Action, name: "commit_projection_reject", schema: Zoi.object(%{})
  def run(_params, _context), do: {:error, :rejected}
end

defmodule JidoTest.CommitProjection.Agent do
  @moduledoc false
  use Jido.Agent,
    name: "commit_projection_agent",
    schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
    routes: [
      {"projection.update", JidoTest.CommitProjection.Update},
      {"projection.reject", JidoTest.CommitProjection.Reject}
    ],
    plugins: [
      {JidoTest.CommitProjection.First, key: :first, sink: JidoTest.CommitProjection.Sink}
    ]
end

defmodule JidoTest.CommitProjection.ProjectionAgent do
  @moduledoc false
  use Jido.Agent,
    name: "runtime_commit_projection_agent",
    schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
    routes: [{"projection.update", JidoTest.CommitProjection.Update}],
    plugins: [
      {JidoTest.CommitProjection.Projection,
       key: :projection, observer: JidoTest.CommitProjection.Observer}
    ]
end

defmodule JidoTest.CommitProjection.TimeoutAgent do
  @moduledoc false
  use Jido.Agent,
    name: "timeout_commit_projection_agent",
    schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
    routes: [{"projection.update", JidoTest.CommitProjection.Update}],
    plugins: [
      {JidoTest.CommitProjection.First,
       key: :first,
       sink: JidoTest.CommitProjection.Sink,
       observer: JidoTest.CommitProjection.Observer,
       gate: "timeout"}
    ]
end
