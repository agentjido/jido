defmodule Jido.Agent.VersioningTest do
  use ExUnit.Case, async: true

  alias Jido.Agent

  defmodule DefaultVersionAgent do
    use Jido.Agent, name: "default_version_agent"
  end

  defmodule VersionedAgent do
    use Jido.Agent, name: "versioned_agent", vsn: 3

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end
  end

  defmodule CustomCheckpointAgent do
    use Jido.Agent, name: "custom_checkpoint_version_agent", vsn: 4

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    @impl Jido.Agent
    def checkpoint(agent, _context), do: {:ok, %{id: agent.id, state: agent.state}}

    @impl Jido.Agent
    def restore(%{id: id, state: state}, _context), do: instantiate(id: id, state: state)
  end

  defmodule NumericDefinitionAgent do
    use Jido.Agent, name: "numeric_definition_agent", metadata: %{ratio: 1}

    state do
      schema Zoi.object(%{count: Zoi.number() |> Zoi.default(1)})
    end
  end

  test "definitions and instances have a positive definition version" do
    assert DefaultVersionAgent.vsn() == 1
    assert VersionedAgent.vsn() == 3
    assert VersionedAgent.definition().vsn == 3
    assert VersionedAgent.instantiate!(id: "version").vsn == 3
    assert Agent.define!(%{name: "default"}).vsn == 1
    assert Agent.define!(%{name: "explicit", vsn: 7}).vsn == 7

    for invalid <- [nil, 0, -1, 1.0, "1", :one] do
      assert {:error, %{path: [:vsn]}} = Agent.define(%{name: "invalid", vsn: invalid})
    end
  end

  test "invalid module versions fail Spark option validation" do
    module = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

    assert_raise Spark.Options.ValidationError, fn ->
      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            use Jido.Agent, name: "invalid_version", vsn: 0
          end
        end
      )
    end
  end

  test "JSON format and definition version are distinct" do
    for value <- [
          VersionedAgent.definition(),
          VersionedAgent.instantiate!(id: "json"),
          Agent.define!(%{name: "data", vsn: 8})
        ] do
      registry = JidoTest.AgentRegistry.for(value)
      assert {:ok, document} = JidoTest.AgentRegistry.encode(value, registry)
      assert document["vsn"] == 2
      assert document["definition"]["vsn"] == value.vsn
      expected = Agent.definition(value)
      assert {:ok, ^expected} = JidoTest.AgentRegistry.decode(document, registry)
      assert {:error, _} = JidoTest.AgentRegistry.decode(%{document | "vsn" => 99}, registry)
    end
  end

  test "snapshots retain the accepted definition without a source definition lookup" do
    original = VersionedAgent.instantiate!(id: "accepted", state: %{count: 5})
    changed = %{original | metadata: %{changed: true}, vsn: 9}
    assert {:ok, snapshot} = Jido.Persistence.snapshot(changed)
    assert snapshot.format == 2
    assert snapshot.agent === changed
    assert snapshot.state_format == :default
    assert {:ok, ^changed} = Jido.Persistence.restore(snapshot)
    assert VersionedAgent.vsn() == 3
    assert original.metadata == %{}
  end

  test "snapshots keep exact numeric values in schemas and metadata" do
    agent = NumericDefinitionAgent.instantiate!(id: "exact")

    for changed <- [
          agent,
          %{agent | metadata: %{ratio: 1.0}},
          %{agent | schema: Zoi.object(%{count: Zoi.number() |> Zoi.default(1.0)})}
        ] do
      assert {:ok, snapshot} = Jido.Persistence.snapshot(changed)
      assert snapshot.agent === changed
      assert {:ok, restored} = Jido.Persistence.restore(snapshot)
      assert restored === changed
    end
  end

  test "old envelopes need explicit conversion" do
    for snapshot <- [%{version: 1, kind: :agent}, %{fmt: 4, kind: :agent, state: %{}}] do
      assert {:error, _} = Jido.Persistence.restore(snapshot)
    end
  end

  test "custom callbacks convert state under the same saved definition" do
    agent = CustomCheckpointAgent.instantiate!(id: "custom", state: %{count: 9})
    assert {:ok, snapshot} = Jido.Persistence.snapshot(agent)
    assert snapshot.state_format == :custom
    assert snapshot.agent.state == %{id: "custom", state: %{count: 9}}
    assert Agent.definition(snapshot.agent) === Agent.definition(agent)
    assert Map.has_key?(snapshot.references, CustomCheckpointAgent)
    assert {:ok, ^agent} = Jido.Persistence.restore(snapshot)
    assert {:error, _} = Jido.Persistence.restore(snapshot.agent.state)
    assert {:ok, changed} = Jido.Persistence.snapshot(%{agent | vsn: 5})
    assert {:ok, %{vsn: 5}} = Jido.Persistence.restore(changed)
  end
end
