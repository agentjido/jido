defmodule JidoTest.SupervisedCounter.Runtime do
  use Jido.Plugin

  @impl true
  def child_spec(init), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [init]}}

  def start_link(init) do
    case :persistent_term.get({__MODULE__, init.jido}, :ok) do
      :ok -> Elixir.Agent.start_link(fn -> init end)
      :fail -> {:error, :runtime_unavailable}
    end
  end
end

defmodule JidoTest.SupervisedCounter do
  use Jido.Agent, name: "supervised_counter"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    plugin JidoTest.SupervisedCounter.Runtime, config: [label: "current"]
  end

  routes do
    signal_source "/test/supervised"

    route "supervised.increment", as: :increment do
      action _input, context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
      end
    end

    route "supervised.reject", as: :reject do
      action _input, context: context do
        {:ok, %{context.agent_state | count: "invalid"}}
      end
    end
  end
end
