defmodule Jido.Agent.SchemaTest do
  use JidoTest.Case, async: true

  @moduletag :basic_contract

  alias Jido.AgentServer, as: Server

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
    defdelegate state_spec(opts), to: Jido.Agent.SchemaTest.OwnedState.Agent
  end

  defmodule OwnedState.Agent do
    @behaviour Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(0)}
  end

  defmodule RequiredState do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate state_spec(opts), to: Jido.Agent.SchemaTest.RequiredState.Agent
  end

  defmodule RequiredState.Agent do
    @behaviour Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:owned, Zoi.integer()}
  end

  defmodule ConfiguredState do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate state_spec(opts), to: Jido.Agent.SchemaTest.ConfiguredState.Agent
  end

  defmodule ConfiguredState.Agent do
    @behaviour Jido.Plugin

    @impl true
    def state_spec(opts), do: {:owned, Zoi.integer() |> Zoi.min(Keyword.fetch!(opts, :minimum))}
  end

  defmodule PlainAgent do
    @moduledoc false

    use Jido.Agent, name: "schema_contract_plain"

    state do
      schema Bounds.schema()
    end

    routes do
      route "counter.add", JidoTest.AgentFixtures.Add
    end
  end

  defmodule PluginAgent do
    @moduledoc false

    use Jido.Agent, name: "schema_contract_plugin"

    state do
      schema Bounds.schema()
    end

    plugins do
      plugin OwnedState
    end

    routes do
      route "counter.add", JidoTest.AgentFixtures.Add
    end
  end

  test "composition preserves required Plugin fields and the root rule" do
    definition = %{PlainAgent.definition() | extensions: [contribution(RequiredState)]}

    assert {:error, %Jido.Agent.Error{details: %{issues: errors}}} =
             Jido.Agent.instantiate(definition, id: Jido.Signal.ID.generate!())

    assert Enum.any?(errors, &(&1.code == :required and &1.path == [:owned]))

    assert {:ok, agent} =
             Jido.Agent.instantiate(definition,
               id: Jido.Signal.ID.generate!(),
               state: %{owned: 7}
             )

    assert agent.state == %{count: 0, history: [], owned: 7}

    assert {:error, %{__exception__: true}} =
             Jido.Agent.instantiate(definition,
               id: Jido.Signal.ID.generate!(),
               state: %{owned: 7, count: 2}
             )
  end

  test "validation composes the current Plugin options and domain schema on each call" do
    definition = %{
      PlainAgent.definition()
      | extensions: [contribution(ConfiguredState, %{minimum: 0})]
    }

    assert {:ok, agent} =
             Jido.Agent.instantiate(definition,
               id: Jido.Signal.ID.generate!(),
               state: %{owned: 0}
             )

    assert {:ok, ^agent} = Jido.Agent.validate(agent)

    changed = %{agent | extensions: [contribution(ConfiguredState, %{minimum: 1})]}
    assert {:error, %{__exception__: true}} = Jido.Agent.validate(changed)

    changed = %{changed | state: %{changed.state | owned: 1}}
    assert {:ok, ^changed} = Jido.Agent.validate(changed)

    changed = %{
      changed
      | schema: Zoi.object(%{count: Zoi.string(), history: Zoi.list(Zoi.string())})
    }

    assert {:error, %{__exception__: true}} = Jido.Agent.validate(changed)
  end

  for {label, agent_module} <- [
        {"without Plugins", PlainAgent},
        {"with owned Plugin state", PluginAgent}
      ] do
    @tag agent_module: agent_module
    test "construction enforces the root refinement #{label}", %{agent_module: agent_module} do
      assert {:ok, %{count: 0, history: []}} =
               Zoi.parse(agent_module.definition().schema, %{count: 0, history: []})

      assert {:error, [_ | _]} =
               Zoi.parse(agent_module.definition().schema, %{count: 2, history: []})

      assert {:error, %{__exception__: true}} =
               agent_module.instantiate(id: "invalid", state: %{count: 2})
    end

    @tag agent_module: agent_module
    test "cmd rejects a candidate outside the root refinement #{label}", %{
      agent_module: agent_module
    } do
      agent = agent_module.instantiate!(id: unique_id())
      command = signal("counter.add", %{by: 2, label: "invalid"})

      assert {:error, %{__exception__: true}} = agent_module.cmd(agent, command)
    end

    @tag agent_module: agent_module
    test "Server rejects an invalid candidate without a commit #{label}", %{
      jido: jido,
      agent_module: agent_module
    } do
      {:ok, server} =
        JidoTest.AgentServerAssertions.start_agent(jido, agent_module, id: unique_id())

      before = JidoTest.AgentServerAssertions.committed(server)
      command = signal("counter.add", %{by: 2, label: "invalid"})

      assert {:error, %{__exception__: true}} = Server.call(server, command)
      assert JidoTest.AgentServerAssertions.committed(server) == before
    end

    @tag agent_module: agent_module
    test "a candidate at the root bound commits once #{label}", %{
      jido: jido,
      agent_module: agent_module
    } do
      {:ok, server} =
        JidoTest.AgentServerAssertions.start_agent(jido, agent_module, id: unique_id())

      initial = Server.agent(server).state
      expected = %{initial | count: 1, history: ["valid"]}

      assert {:ok, agent, _} =
               Server.call(server, signal("counter.add", %{by: 1, label: "valid"}))

      assert agent.state == expected
      assert %{agent: ^agent, state_version: 1} = JidoTest.AgentServerAssertions.committed(server)
    end
  end

  defp contribution(provider, data \\ %{}),
    do: %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}
end
