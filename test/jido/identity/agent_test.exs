defmodule JidoTest.Identity.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Identity
  alias Jido.Identity.Agent, as: IdentityAgent

  defp create_agent do
    %Agent{id: "test-agent-1", state: %{}}
  end

  describe "key/0" do
    test "returns :__identity__" do
      assert IdentityAgent.key() == :__identity__
    end
  end

  describe "get/2" do
    test "returns nil when no identity present" do
      agent = create_agent()
      assert IdentityAgent.get(agent) == nil
    end

    test "returns default when no identity present" do
      agent = create_agent()
      default = Identity.new()
      assert IdentityAgent.get(agent, default) == default
    end

    test "returns identity when present" do
      identity = Identity.new()
      agent = %{create_agent() | state: %{__identity__: identity}}
      assert IdentityAgent.get(agent) == identity
    end
  end

  describe "put/2" do
    test "stores identity in agent state" do
      agent = create_agent()
      identity = Identity.new()

      updated = IdentityAgent.put(agent, identity)

      assert updated.state[:__identity__] == identity
      assert IdentityAgent.get(updated) == identity
    end

    test "preserves other state keys" do
      agent = %{create_agent() | state: %{foo: :bar}}
      identity = Identity.new()

      updated = IdentityAgent.put(agent, identity)

      assert updated.state[:foo] == :bar
      assert updated.state[:__identity__] == identity
    end
  end

  describe "update/2" do
    test "updates identity using function" do
      identity = Identity.new(profile: %{age: 5})
      agent = IdentityAgent.put(create_agent(), identity)

      updated =
        IdentityAgent.update(agent, fn id ->
          Identity.evolve(id, years: 1)
        end)

      result = IdentityAgent.get(updated)
      assert result.profile[:age] == 6
    end

    test "passes nil to function when no identity" do
      agent = create_agent()

      updated =
        IdentityAgent.update(agent, fn id ->
          assert id == nil
          Identity.new()
        end)

      assert %Identity{} = IdentityAgent.get(updated)
    end
  end

  describe "ensure/2" do
    test "creates identity if missing" do
      agent = create_agent()
      assert IdentityAgent.has_identity?(agent) == false

      updated = IdentityAgent.ensure(agent)

      assert IdentityAgent.has_identity?(updated) == true
      assert %Identity{} = IdentityAgent.get(updated)
    end

    test "passes opts to Identity.new" do
      agent = create_agent()

      updated = IdentityAgent.ensure(agent, profile: %{age: 10})

      identity = IdentityAgent.get(updated)
      assert identity.profile == %{age: 10}
    end

    test "does NOT overwrite existing identity" do
      identity = Identity.new(profile: %{age: 42})
      agent = IdentityAgent.put(create_agent(), identity)

      updated = IdentityAgent.ensure(agent, profile: %{age: 0})

      result = IdentityAgent.get(updated)
      assert result.profile == %{age: 42}
    end
  end

  describe "has_identity?/1" do
    test "returns false when no identity" do
      agent = create_agent()
      assert IdentityAgent.has_identity?(agent) == false
    end

    test "returns true when identity present" do
      agent = IdentityAgent.put(create_agent(), Identity.new())
      assert IdentityAgent.has_identity?(agent) == true
    end
  end

  describe "snapshot/1" do
    test "returns nil when no identity" do
      agent = create_agent()
      assert IdentityAgent.snapshot(agent) == nil
    end

    test "returns snapshot when present" do
      identity = Identity.new(profile: %{age: 5})
      agent = IdentityAgent.put(create_agent(), identity)
      snap = IdentityAgent.snapshot(agent)
      assert is_map(snap)
      assert snap[:profile][:age] == 5
      refute Map.has_key?(snap, :capabilities)
    end
  end
end
