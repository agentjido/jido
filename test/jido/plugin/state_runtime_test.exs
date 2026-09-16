defmodule Jido.Plugin.StateRuntimeTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule Spend do
    @schema Zoi.struct(__MODULE__, %{amount: Zoi.integer() |> Zoi.min(1)})
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
    def validate(%__MODULE__{} = directive), do: Zoi.parse(@schema, directive)
  end

  defmodule Credits do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule Credits.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(_opts), do: {:credits, Zoi.integer() |> Zoi.min(0) |> Zoi.default(3)}

    @impl true
    def directives(_opts), do: [Spend]

    @impl true
    def reduce(reduction, _opts),
      do:
        {:ok,
         Enum.reduce(reduction.directives, reduction.plugin_state, fn
           %Spend{amount: amount}, left -> left - amount
           _directive, left -> left
         end)}
  end

  defmodule SpendCredits do
    use Jido.Action, name: "plugin_spend_credits"

    @impl Jido.Action
    def run(%{amount: amount}, context) do
      {:ok, context.agent_state, [%Spend{amount: amount}]}
    end
  end

  defmodule DataAgent do
    use Jido.Agent,
      name: "plugin_data_agent",
      routes: [{"plugin.credits.spend", SpendCredits}],
      plugins: [Credits]
  end

  test "state-only Plugins compose optional state into the Agent" do
    agent = DataAgent.new!()

    assert agent.state == %{credits: 3}
    assert agent.schema.fields == []
    assert Keyword.keys(Jido.Agent.complete_schema!(agent).fields) == [:credits]
  end

  test "state-only Plugin Directives update state without a Plugin runtime", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, DataAgent, id: unique_id("plugin-data"))

    signal = Signal.new!("plugin.credits.spend", %{amount: 1}, source: "/test")

    assert {:ok, agent} = Server.call(pid, signal)
    assert agent.state.credits == 2
    assert Server.children(pid) == %{}
  end
end
