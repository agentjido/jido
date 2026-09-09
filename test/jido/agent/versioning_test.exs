defmodule Jido.Agent.VersioningTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.{Builder, Codec}

  defmodule DefaultVersionAgent do
    use Jido.Agent, name: "default_version_agent"
  end

  defmodule VersionedAgent do
    use Jido.Agent,
      name: "versioned_agent",
      vsn: 3,
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  defmodule CustomCheckpointAgent do
    use Jido.Agent,
      name: "custom_checkpoint_version_agent",
      vsn: 4,
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})

    @impl Jido.Agent
    def checkpoint(agent, _context), do: {:ok, %{id: agent.id, state: agent.state}}

    @impl Jido.Agent
    def restore(%{id: id, state: state}, _context), do: new(id: id, state: state)
  end

  test "generated modules own a positive version and direct definitions can be unversioned" do
    assert DefaultVersionAgent.vsn() == 1
    assert DefaultVersionAgent.agent().vsn == 1
    assert DefaultVersionAgent.new!().vsn == 1

    assert VersionedAgent.vsn() == 3
    assert VersionedAgent.agent().vsn == 3
    assert VersionedAgent.new!().vsn == 3

    assert Agent.new!(name: "unversioned").vsn == nil
    assert Agent.new!(name: "direct_versioned", vsn: 7).vsn == 7

    for invalid <- [0, -1, 1.0, "1", :one] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.new(name: "invalid_vsn", vsn: invalid)
    end
  end

  test "invalid generated module versions fail during compilation" do
    module = Module.concat(__MODULE__, "InvalidVersion#{System.unique_integer([:positive])}")

    assert_raise CompileError, ~r/Agent vsn must be a positive integer/, fn ->
      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            use Jido.Agent, name: "invalid_generated_version", vsn: 0
          end
        end
      )
    end
  end

  test "definition, map, Builder, and Codec preserve the version" do
    agent = VersionedAgent.new!(id: "versioned", state: %{count: 2})
    assert Agent.definition(agent).vsn == 3
    assert Agent.to_map(agent).vsn == 3

    assert Builder.new(name: "built", vsn: 8) |> Builder.build!() |> Map.fetch!(:vsn) == 8
    assert Builder.new(VersionedAgent) |> Builder.build!() == VersionedAgent.agent()

    assert {:ok, document, registry} = Codec.encode(VersionedAgent.agent())
    assert document["version"] == 2
    assert document["vsn"] == 3
    assert {:ok, %{vsn: 3}} = Codec.decode(document, registry)

    legacy_document = document |> Map.delete("vsn") |> Map.put("version", 1)
    assert {:ok, %{vsn: 1}} = Codec.decode(legacy_document, registry)

    direct = Agent.new!(name: "direct_codec")
    assert {:ok, direct_document, direct_registry} = Codec.encode(direct)
    assert {:ok, %{vsn: nil}} = Codec.decode(direct_document, direct_registry)

    direct_legacy = direct_document |> Map.delete("vsn") |> Map.put("version", 1)
    assert {:ok, %{vsn: nil}} = Codec.decode(direct_legacy, direct_registry)
  end

  test "generated default checkpoints use version 2 and reject changed definitions" do
    agent = VersionedAgent.new!(id: "versioned", state: %{count: 5})

    assert {:ok,
            %{
              version: 2,
              kind: :agent,
              agent_module: VersionedAgent,
              vsn: 3,
              id: "versioned",
              state: %{count: 5}
            } = checkpoint} = Agent.checkpoint(agent)

    assert {:ok, ^agent} = Agent.restore(VersionedAgent, checkpoint)

    changed = %{agent | metadata: %{changed: true}}

    assert {:error, %Jido.Error.ValidationError{details: %{code: :definition_mismatch}} = error} =
             Agent.checkpoint(changed)

    assert Jido.Error.code(error) == :definition_mismatch
  end

  test "default restore rejects module and version mismatches before state acceptance" do
    agent = VersionedAgent.new!(id: "versioned", state: %{count: 5})
    assert {:ok, checkpoint} = Agent.checkpoint(agent)

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.restore(DefaultVersionAgent, checkpoint)

    assert {:error, %Jido.Error.ValidationError{details: %{code: :definition_mismatch}}} =
             Agent.restore(VersionedAgent, %{checkpoint | vsn: 2})
  end

  test "version-1 generated checkpoints imply version 1" do
    agent = DefaultVersionAgent.new!(id: "legacy")

    checkpoint = %{
      version: 1,
      kind: :agent,
      agent_module: DefaultVersionAgent,
      id: agent.id,
      definition: Agent.definition(agent),
      state: agent.state
    }

    assert {:ok, ^agent} = Agent.restore(DefaultVersionAgent, checkpoint)

    versioned_checkpoint = %{checkpoint | agent_module: VersionedAgent}

    assert {:error, %Jido.Error.ValidationError{details: %{code: :definition_mismatch}}} =
             Agent.restore(VersionedAgent, versioned_checkpoint)
  end

  test "an explicit unversioned definition derived from a generated module stays embedded" do
    definition = %{VersionedAgent.agent() | vsn: nil, metadata: %{owner: :application}}
    agent = Agent.instantiate!(definition, id: "derived", state: %{count: 2})

    assert {:ok, %{version: 1, definition: ^definition} = checkpoint} =
             Agent.checkpoint(agent)

    assert {:ok, ^agent} = Agent.restore(VersionedAgent, checkpoint)
  end

  test "custom callbacks use a core envelope and accept legacy raw payloads" do
    agent = CustomCheckpointAgent.new!(id: "custom", state: %{count: 9})
    assert {:ok, checkpoint} = Agent.checkpoint(agent)

    assert checkpoint == %{
             version: 2,
             kind: :agent_custom,
             agent_module: CustomCheckpointAgent,
             vsn: 4,
             payload: %{id: "custom", state: %{count: 9}}
           }

    assert {:ok, ^agent} = Agent.restore(CustomCheckpointAgent, checkpoint)
    assert {:ok, ^agent} = Agent.restore(CustomCheckpointAgent, checkpoint.payload)

    assert {:error, %Jido.Error.ValidationError{details: %{code: :definition_mismatch}}} =
             Agent.restore(CustomCheckpointAgent, %{checkpoint | vsn: 3})

    assert {:error, %Jido.Error.ValidationError{details: %{code: :definition_mismatch}}} =
             Agent.checkpoint(%{agent | vsn: 3})
  end
end
