defmodule JidoTest.AgentEvolutionFixtures do
  defmodule Work do
    use Jido.Action, name: "evolution_work"
    def run(input, context), do: {:ok, context.agent_state, Map.get(input, :directives, [])}
  end

  defmodule Worker do
    use Jido.Agent, name: "evolution_worker"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "work", JidoTest.AgentEvolutionFixtures.Work
    end
  end

  defmodule Flow do
    use Jido.Flow, name: "evolution_flow"

    flow do
      step "work", action: JidoTest.AgentEvolutionFixtures.Work, params: input()
      output result("work")
    end
  end

  defmodule Owned do
    use Jido.Agent.Directive
    defstruct []
  end

  defmodule Counter do
    use Jido.Plugin, id: "evolution.counter"
    def state_spec(opts), do: {Keyword.get(opts, :key, :counter), Zoi.integer() |> Zoi.default(3)}
    def directives(_), do: [JidoTest.AgentEvolutionFixtures.Owned]
    def reduce(reduction, _), do: {:ok, reduction.plugin_state}
    def dump(value, _, _), do: {:ok, %{saved: value}}
    def load(%{saved: value}, _, _), do: {:ok, value}
  end

  defmodule Migrations do
    def add(value, n), do: {:ok, value + n}
    def fail(_), do: {:error, :migration_failed}
  end

  defmodule Checks do
    def valid(_, _), do: :ok
  end

  defmodule Transform do
    def run(signal), do: {:ok, %{signal | type: "normalized"}}
  end

  defmodule Upgrade do
    use Jido.Action,
      name: "evolution_upgrade"

    def run(%{snapshot: snapshot}, _) do
      agent = %{snapshot.agent | routes: [], state: %{count: 7}}
      with {:ok, next} <- Jido.Persistence.snapshot(agent), do: {:ok, %{snapshot: next}}
    end
  end

  defmodule Custom do
    use Jido.Agent, name: "evolution_custom"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    def checkpoint(agent, _), do: {:ok, %{id: agent.id, saved: agent.state.count}}

    def restore(payload, context) do
      if context[:observer], do: send(context.observer, :restored)
      instantiate(id: payload.id, state: %{count: payload.saved})
    end
  end

  defmodule BadUpgrade do
    use Jido.Action,
      name: "evolution_bad_upgrade"

    def run(%{snapshot: snapshot}, context) do
      case context.mode do
        :identity -> {:ok, %{snapshot: put_in(snapshot.agent.id, "other")}}
        :origin -> {:ok, %{snapshot: put_in(snapshot.agent.module, OtherOrigin)}}
        :state -> {:ok, %{snapshot: put_in(snapshot.agent.state.count, "wrong")}}
        :directive -> {:ok, %{snapshot: snapshot}, [Jido.AgentServer.Directive.server_stop()]}
        :result -> {:ok, %{wrong: true}}
        :extra -> {:ok, %{snapshot: snapshot, ignored: true}}
        :nonportable -> {:ok, %{snapshot: Map.put(snapshot, :pid, self())}}
        :raise -> raise "upgrade failed"
      end
    end
  end

  def agent do
    Jido.Agent.define!(%{
      name: "evolution",
      signal_source: "/evolution",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      routes: [
        %{
          path: "run",
          handler: %{kind: :action, target: Work},
          state: %{source: :output, path: []}
        }
      ]
    })
    |> Jido.Agent.instantiate!(id: "evolution")
  end

  def signal(directives), do: Jido.Signal.new!("run", %{directives: directives}, source: "/test")
end
