defmodule JidoTest.Authoring.Agents.Fixtures.Add do
  use Jido.Action,
    name: "authoring_corpus_add",
    schema: Zoi.object(%{amount: Zoi.integer()})

  def run(%{amount: amount}, %{agent_state: state}),
    do: {:ok, %{state | count: state.count + amount}}
end

defmodule JidoTest.Authoring.Agents.Fixtures.AddFlow do
  use Jido.Flow,
    name: "authoring_corpus_flow",
    schema: Zoi.object(%{amount: Zoi.integer()})

  flow do
    step "add", action: JidoTest.Authoring.Agents.Fixtures.Add, params: %{amount: input(:amount)}
    output result("add")
  end
end

defmodule JidoTest.Authoring.Agents.Fixtures.CountTurns do
  use Jido.Plugin, agent: __MODULE__.Agent
end

defmodule JidoTest.Authoring.Agents.Fixtures.CountTurns.Agent do
  use Jido.Agent.Plugin

  def state_spec(opts),
    do: {:turns, Zoi.integer() |> Zoi.default(Keyword.fetch!(opts, :initial))}

  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end
