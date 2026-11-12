defmodule Jido.Agent.SchemaTest do
  use Jido.Test.Case, async: true

  @moduletag :basic_contract

  alias Jido.AgentServer, as: Server

  defmodule Bounds do
    @moduledoc false

    def schema do
      Jido.Joi.object(%{
        count: Jido.Joi.integer() |> Jido.Joi.default(0),
        history: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])
      })
      |> Jido.Joi.refine({__MODULE__, :within_bound, []})
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
    def state_spec(_opts), do: {:owned, Jido.Joi.integer() |> Jido.Joi.default(0)}
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
    def state_spec(_opts), do: {:owned, Jido.Joi.integer()}
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
    def state_spec(opts), do: {:owned, Jido.Joi.integer() |> Jido.Joi.min(Keyword.fetch!(opts, :minimum))}
  end

  defmodule PlainAgent do
    @moduledoc false

    use Jido.Agent, name: "schema_contract_plain"

    state do
      schema Bounds.schema()
    end

    routes do
      route "counter.add", Jido.Test.AgentServer.Fixtures.Add
    end
  end

  defmodule PluginAgent do
    @moduledoc false

    use Jido.Agent, name: "schema_contract_plugin", plugins: [OwnedState]

    state do
      schema Bounds.schema()
    end

    routes do
      route "counter.add", Jido.Test.AgentServer.Fixtures.Add
    end
  end

  test "composition preserves required Plugin fields and the root rule" do
    definition = %{PlainAgent.definition() | plugins: [contribution(RequiredState)]}

    assert {:error, %Jido.Error.ValidationError{details: %{issues: errors}}} =
             Jido.Agent.instantiate(definition, id: Jido.Id.uuid7())

    assert Enum.any?(errors, &(&1.code == :required and &1.path == [:owned]))

    assert {:ok, agent} =
             Jido.Agent.instantiate(definition,
               id: Jido.Id.uuid7(),
               state: %{owned: 7}
             )

    assert agent.state == %{count: 0, history: [], owned: 7}

    assert {:error, %{__exception__: true}} =
             Jido.Agent.instantiate(definition,
               id: Jido.Id.uuid7(),
               state: %{owned: 7, count: 2}
             )
  end

  test "validation composes the current Plugin options and domain schema on each call" do
    definition = %{
      PlainAgent.definition()
      | plugins: [contribution(ConfiguredState, %{minimum: 0})]
    }

    assert {:ok, agent} =
             Jido.Agent.instantiate(definition,
               id: Jido.Id.uuid7(),
               state: %{owned: 0}
             )

    assert {:ok, ^agent} = Jido.Agent.validate(agent)

    changed = %{agent | plugins: [contribution(ConfiguredState, %{minimum: 1})]}
    assert {:error, %{__exception__: true}} = Jido.Agent.validate(changed)

    changed = %{changed | state: %{changed.state | owned: 1}}
    assert {:ok, ^changed} = Jido.Agent.validate(changed)

    changed = %{
      changed
      | schema: Jido.Joi.object(%{count: Jido.Joi.string(), history: Jido.Joi.list(Jido.Joi.string())})
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
               Jido.Joi.parse(agent_module.definition().schema, %{count: 0, history: []})

      assert {:error, [_ | _]} =
               Jido.Joi.parse(agent_module.definition().schema, %{count: 2, history: []})

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
        Jido.Test.AgentServer.Assertions.start_agent(jido, agent_module, id: unique_id())

      before = Jido.Test.AgentServer.Assertions.committed(server)
      command = signal("counter.add", %{by: 2, label: "invalid"})

      assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
               Server.call(server, command)

      assert Jido.Test.AgentServer.Assertions.committed(server) == before
    end

    @tag agent_module: agent_module
    test "a candidate at the root bound commits once #{label}", %{
      jido: jido,
      agent_module: agent_module
    } do
      {:ok, server} =
        Jido.Test.AgentServer.Assertions.start_agent(jido, agent_module, id: unique_id())

      initial = Server.snapshot(server).agent.state
      expected = %{initial | count: 1, history: ["valid"]}

      assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
               Server.call(server, signal("counter.add", %{by: 1, label: "valid"}))

      agent = Server.snapshot(server).agent
      assert agent.state == expected
      assert %{agent: ^agent, state_version: 1} = Jido.Test.AgentServer.Assertions.committed(server)
    end
  end

  defp contribution(provider, data \\ %{}),
    do: %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}
end
