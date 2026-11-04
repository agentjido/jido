defmodule Jido.Test.AgentServer.CommitProjection.Effect do
  @moduledoc false
  use Jido.Agent.Directive
  defstruct [:sink]
end

defmodule Jido.Test.AgentServer.CommitProjection.AgentFacet do
  @moduledoc false
  @behaviour Jido.Plugin

  def state_spec(opts), do: {Keyword.fetch!(opts, :key), Jido.Joi.integer() |> Jido.Joi.default(0)}

  def directives(opts),
    do: if(opts[:key] == :first, do: [Jido.Test.AgentServer.CommitProjection.Effect], else: [])

  def reduce(reduction, _opts), do: {:ok, reduction.candidate_state.count}
end

defmodule Jido.Test.AgentServer.CommitProjection.ServerFacet do
  @moduledoc false
  @behaviour Jido.Plugin

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
          Jido.AgentServer.call(server, Jido.Test.Case.signal("projection.update", %{amount: 1}))

        send(opts[:observer], {:reentrant_result, result})
        :ok
    end
  end

  def dispatch(_runtime, %{sink: sink}, _context, _opts) do
    Agent.update(sink, &(&1 ++ [:effect]))
  end
end

defmodule Jido.Test.AgentServer.CommitProjection.First do
  @moduledoc false
  use Jido.Plugin

  @impl true
  defdelegate state_spec(opts), to: Jido.Test.AgentServer.CommitProjection.AgentFacet

  @impl true
  defdelegate directives(opts), to: Jido.Test.AgentServer.CommitProjection.AgentFacet

  @impl true
  defdelegate reduce(reduction, opts), to: Jido.Test.AgentServer.CommitProjection.AgentFacet

  @impl true
  defdelegate after_commit(runtime, commit, opts), to: Jido.Test.AgentServer.CommitProjection.ServerFacet

  @impl true
  defdelegate dispatch(runtime, directive, context, opts),
    to: Jido.Test.AgentServer.CommitProjection.ServerFacet
end

defmodule Jido.Test.AgentServer.CommitProjection.Second do
  @moduledoc false
  use Jido.Plugin

  @impl true
  defdelegate state_spec(opts), to: Jido.Test.AgentServer.CommitProjection.AgentFacet

  @impl true
  defdelegate directives(opts), to: Jido.Test.AgentServer.CommitProjection.AgentFacet

  @impl true
  defdelegate reduce(reduction, opts), to: Jido.Test.AgentServer.CommitProjection.AgentFacet

  @impl true
  defdelegate after_commit(runtime, commit, opts), to: Jido.Test.AgentServer.CommitProjection.NotificationFacet
end

defmodule Jido.Test.AgentServer.CommitProjection.NotificationFacet do
  @moduledoc false
  @behaviour Jido.Plugin
  defdelegate after_commit(runtime, commit, opts), to: Jido.Test.AgentServer.CommitProjection.ServerFacet
end

defmodule Jido.Test.AgentServer.CommitProjection.Stateless do
  @moduledoc false
  use Jido.Plugin

  @impl true
  defdelegate after_commit(runtime, commit, opts), to: Jido.Test.AgentServer.CommitProjection.NotificationFacet
end

defmodule Jido.Test.AgentServer.CommitProjection.Runtime do
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

defmodule Jido.Test.AgentServer.CommitProjection.RuntimeFacet do
  @moduledoc false
  @behaviour Jido.Plugin

  def child_spec(init), do: Supervisor.child_spec({Jido.Test.AgentServer.CommitProjection.Runtime, init}, [])
  def after_commit(runtime, commit, _opts), do: GenServer.call(runtime, {:commit, commit})
end

defmodule Jido.Test.AgentServer.CommitProjection.Projection do
  @moduledoc false
  use Jido.Plugin

  @impl true
  defdelegate state_spec(opts), to: Jido.Test.AgentServer.CommitProjection.AgentFacet

  @impl true
  defdelegate directives(opts), to: Jido.Test.AgentServer.CommitProjection.AgentFacet

  @impl true
  defdelegate reduce(reduction, opts), to: Jido.Test.AgentServer.CommitProjection.AgentFacet

  @impl true
  defdelegate child_spec(init), to: Jido.Test.AgentServer.CommitProjection.RuntimeFacet

  @impl true
  defdelegate after_commit(runtime, commit, opts), to: Jido.Test.AgentServer.CommitProjection.RuntimeFacet
end

defmodule Jido.Test.AgentServer.CommitProjection.Update do
  @moduledoc false
  use Jido.Action,
    name: "commit_projection_update",
    schema:
      Jido.Joi.object(%{amount: Jido.Joi.integer(), directives: Jido.Joi.list(Jido.Joi.any()) |> Jido.Joi.default([])})

  def run(params, context) do
    {:ok, %{context.agent_state | count: context.agent_state.count + params.amount}, params.directives}
  end
end

defmodule Jido.Test.AgentServer.CommitProjection.Reject do
  @moduledoc false
  use Jido.Action,
    name: "commit_projection_reject",
    schema: Jido.Joi.object(%{})

  def run(_params, _context), do: {:error, :rejected}
end

defmodule Jido.Test.AgentServer.CommitProjection.Agent do
  @moduledoc false
  use Jido.Agent,
    name: "commit_projection_agent",
    plugins: [
      {Jido.Test.AgentServer.CommitProjection.First, %{key: :first, sink: Jido.Test.AgentServer.CommitProjection.Sink}}
    ]

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    route "projection.update", Jido.Test.AgentServer.CommitProjection.Update

    route "projection.reject", Jido.Test.AgentServer.CommitProjection.Reject do
      state(:unchanged)
    end
  end
end

defmodule Jido.Test.AgentServer.CommitProjection.ProjectionAgent do
  @moduledoc false
  use Jido.Agent,
    name: "runtime_commit_projection_agent",
    plugins: [
      {Jido.Test.AgentServer.CommitProjection.Projection,
       %{key: :projection, observer: Jido.Test.AgentServer.CommitProjection.Observer}}
    ]

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    route "projection.update", Jido.Test.AgentServer.CommitProjection.Update
  end
end

defmodule Jido.Test.AgentServer.CommitProjection.TimeoutAgent do
  @moduledoc false
  use Jido.Agent,
    name: "timeout_commit_projection_agent",
    plugins: [
      {Jido.Test.AgentServer.CommitProjection.First,
       %{
         key: :first,
         sink: Jido.Test.AgentServer.CommitProjection.Sink,
         observer: Jido.Test.AgentServer.CommitProjection.Observer,
         gate: "timeout"
       }}
    ]

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    route "projection.update", Jido.Test.AgentServer.CommitProjection.Update
  end
end
