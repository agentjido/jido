defmodule Jido.Agent.SchemaContractTest do
  use JidoTest.Case, async: true

  @moduletag :basic_contract

  alias Jido.AgentServer, as: Server
  alias Jido.Error.ValidationError

  defmodule Bounds do
    @moduledoc false

    def schema do
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.default(0),
        history: Zoi.list(Zoi.string()) |> Zoi.default([])
      })
      |> Zoi.refine({__MODULE__, :within_bound, []})
    end

    def within_bound(%{count: count}, _opts) when count <= 1, do: :ok
    def within_bound(_state, _opts), do: {:error, "count must not exceed one"}
  end

  defmodule OwnedState do
    @moduledoc false

    use Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(0)}
  end

  defmodule RequiredState do
    @moduledoc false

    use Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:owned, Zoi.integer()}
  end

  defmodule PlainAgent do
    @moduledoc false

    use Jido.Agent,
      name: "schema_contract_plain",
      schema: Bounds.schema(),
      routes: [{"counter.add", JidoTest.AgentFixtures.Add}]
  end

  defmodule PluginAgent do
    @moduledoc false

    use Jido.Agent,
      name: "schema_contract_plugin",
      schema: Bounds.schema(),
      plugins: [OwnedState],
      routes: [{"counter.add", JidoTest.AgentFixtures.Add}]
  end

  test "composition preserves required Plugin fields and the root rule" do
    definition = %{PlainAgent.agent() | plugins: [RequiredState]}

    assert {:error, %ValidationError{details: %{errors: errors}}} =
             Jido.Agent.instantiate(definition)

    assert Enum.any?(errors, &(&1.code == :required and &1.path == [:owned]))

    assert {:ok, agent} = Jido.Agent.instantiate(definition, state: %{owned: 7})
    assert agent.state == %{count: 0, history: [], owned: 7}

    assert {:error, %ValidationError{}} =
             Jido.Agent.instantiate(definition, state: %{owned: 7, count: 2})
  end

  for {label, agent_module} <- [
        {"without Plugins", PlainAgent},
        {"with owned Plugin state", PluginAgent}
      ] do
    @tag agent_module: agent_module
    test "construction enforces the root refinement #{label}", %{agent_module: agent_module} do
      assert {:ok, %{count: 0, history: []}} =
               Zoi.parse(agent_module.schema(), %{count: 0, history: []})

      assert {:error, [_ | _]} =
               Zoi.parse(agent_module.schema(), %{count: 2, history: []})

      assert {:error, %ValidationError{}} = agent_module.new(state: %{count: 2})
    end

    @tag agent_module: agent_module
    test "cmd rejects a candidate outside the root refinement #{label}", %{
      agent_module: agent_module
    } do
      agent = agent_module.new!()
      command = signal("counter.add", %{by: 2, label: "invalid"})

      assert {:error, %ValidationError{}} = agent_module.cmd(agent, command)
    end

    @tag agent_module: agent_module
    test "Server rejects an invalid candidate without a commit #{label}", %{
      jido: jido,
      agent_module: agent_module
    } do
      {:ok, server} = Jido.start_agent(jido, agent_module, id: unique_id())
      before = Server.snapshot(server)
      command = signal("counter.add", %{by: 2, label: "invalid"})

      assert {:error, %ValidationError{}} = Server.call(server, command)
      assert Server.snapshot(server) == before
    end

    @tag agent_module: agent_module
    test "a candidate at the root bound commits once #{label}", %{
      jido: jido,
      agent_module: agent_module
    } do
      {:ok, server} = Jido.start_agent(jido, agent_module, id: unique_id())
      initial = Server.snapshot(server).agent.state
      expected = %{initial | count: 1, history: ["valid"]}

      assert {:ok, agent} = Server.call(server, signal("counter.add", %{by: 1, label: "valid"}))
      assert agent.state == expected
      assert %{agent: ^agent, state_version: 1} = Server.snapshot(server)
    end
  end
end
