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
