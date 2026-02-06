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

  describe "age/1" do
    test "returns nil when no identity" do
      agent = create_agent()
      assert IdentityAgent.age(agent) == nil
    end

    test "returns age when present" do
      identity = Identity.new(profile: %{age: 7})
      agent = IdentityAgent.put(create_agent(), identity)
      assert IdentityAgent.age(agent) == 7
    end
  end

  describe "get_profile/3" do
    test "returns default when no identity" do
      agent = create_agent()
      assert IdentityAgent.get_profile(agent, :age, :fallback) == :fallback
    end

    test "returns key value when present" do
      identity = Identity.new(profile: %{age: 3, origin: "lab"})
      agent = IdentityAgent.put(create_agent(), identity)
      assert IdentityAgent.get_profile(agent, :origin) == "lab"
    end
  end

  describe "put_profile/3" do
    test "sets key in profile" do
      agent = IdentityAgent.ensure(create_agent())
      updated = IdentityAgent.put_profile(agent, :origin, "cloud")
      assert IdentityAgent.get_profile(updated, :origin) == "cloud"
    end

    test "bumps rev" do
      agent = IdentityAgent.ensure(create_agent())
      rev_before = IdentityAgent.get(agent).rev
      updated = IdentityAgent.put_profile(agent, :origin, "cloud")
      assert IdentityAgent.get(updated).rev > rev_before
    end
  end

  describe "capabilities/1" do
    test "returns defaults when no identity" do
      agent = create_agent()
      assert IdentityAgent.capabilities(agent) == %{actions: [], tags: [], io: %{}, limits: %{}}
    end

    test "returns capabilities when present" do
      identity =
        Identity.new(capabilities: %{actions: [:foo], tags: [:bar], io: %{}, limits: %{}})

      agent = IdentityAgent.put(create_agent(), identity)

      assert IdentityAgent.capabilities(agent) == %{
               actions: [:foo],
               tags: [:bar],
               io: %{},
               limits: %{}
             }
    end
  end

  describe "supports_action?/2" do
    test "returns true when action present" do
      identity = Identity.new(capabilities: %{actions: [:run], tags: [], io: %{}, limits: %{}})
      agent = IdentityAgent.put(create_agent(), identity)
      assert IdentityAgent.supports_action?(agent, :run) == true
    end

    test "returns false when action absent" do
      agent = IdentityAgent.ensure(create_agent())
      assert IdentityAgent.supports_action?(agent, :run) == false
    end
  end

  describe "has_tag?/2" do
    test "returns true when tag present" do
      identity = Identity.new(capabilities: %{actions: [], tags: [:fast], io: %{}, limits: %{}})
      agent = IdentityAgent.put(create_agent(), identity)
      assert IdentityAgent.has_tag?(agent, :fast) == true
    end

    test "returns false when tag absent" do
      agent = IdentityAgent.ensure(create_agent())
      assert IdentityAgent.has_tag?(agent, :fast) == false
    end
  end

  describe "actions/1" do
    test "returns action list" do
      identity = Identity.new(capabilities: %{actions: [:a, :b], tags: [], io: %{}, limits: %{}})
      agent = IdentityAgent.put(create_agent(), identity)
      assert IdentityAgent.actions(agent) == [:a, :b]
    end
  end

  describe "tags/1" do
    test "returns tag list" do
      identity = Identity.new(capabilities: %{actions: [], tags: [:x, :y], io: %{}, limits: %{}})
      agent = IdentityAgent.put(create_agent(), identity)
      assert IdentityAgent.tags(agent) == [:x, :y]
    end
  end

  describe "add_action/2" do
    test "adds action" do
      agent = IdentityAgent.ensure(create_agent())
      updated = IdentityAgent.add_action(agent, :run)
      assert :run in IdentityAgent.actions(updated)
    end

    test "does not duplicate" do
      agent = IdentityAgent.ensure(create_agent())
      updated = agent |> IdentityAgent.add_action(:run) |> IdentityAgent.add_action(:run)
      assert IdentityAgent.actions(updated) == [:run]
    end

    test "bumps rev" do
      agent = IdentityAgent.ensure(create_agent())
      rev_before = IdentityAgent.get(agent).rev
      updated = IdentityAgent.add_action(agent, :run)
      assert IdentityAgent.get(updated).rev > rev_before
    end
  end

  describe "remove_action/2" do
    test "removes action" do
      agent = IdentityAgent.ensure(create_agent()) |> IdentityAgent.add_action(:run)
      updated = IdentityAgent.remove_action(agent, :run)
      refute :run in IdentityAgent.actions(updated)
    end
  end

  describe "add_tag/2" do
    test "adds tag" do
      agent = IdentityAgent.ensure(create_agent())
      updated = IdentityAgent.add_tag(agent, :fast)
      assert :fast in IdentityAgent.tags(updated)
    end

    test "does not duplicate" do
      agent = IdentityAgent.ensure(create_agent())
      updated = agent |> IdentityAgent.add_tag(:fast) |> IdentityAgent.add_tag(:fast)
      assert IdentityAgent.tags(updated) == [:fast]
    end
  end

  describe "set_limit/3" do
    test "sets limit value" do
      agent = IdentityAgent.ensure(create_agent())
      updated = IdentityAgent.set_limit(agent, :max_tokens, 1000)
      assert IdentityAgent.capabilities(updated)[:limits] == %{max_tokens: 1000}
    end
  end

  describe "set_io/3" do
    test "sets io value" do
      agent = IdentityAgent.ensure(create_agent())
      updated = IdentityAgent.set_io(agent, :input, :text)
      assert IdentityAgent.capabilities(updated)[:io] == %{input: :text}
    end
  end

  describe "get_extension/3" do
    test "returns default when no identity" do
      agent = create_agent()
      assert IdentityAgent.get_extension(agent, :plugin_a, :none) == :none
    end

    test "returns extension when present" do
      identity = Identity.new(extensions: %{plugin_a: %{key: "val"}})
      agent = IdentityAgent.put(create_agent(), identity)
      assert IdentityAgent.get_extension(agent, :plugin_a) == %{key: "val"}
    end
  end

  describe "put_extension/3" do
    test "puts extension map" do
      agent = IdentityAgent.ensure(create_agent())
      updated = IdentityAgent.put_extension(agent, :plugin_a, %{key: "val"})
      assert IdentityAgent.get_extension(updated, :plugin_a) == %{key: "val"}
    end
  end

  describe "merge_extension/3" do
    test "shallow merges into extension" do
      agent =
        IdentityAgent.ensure(create_agent())
        |> IdentityAgent.put_extension(:plugin_a, %{a: 1, b: 2})

      updated = IdentityAgent.merge_extension(agent, :plugin_a, %{b: 99, c: 3})
      assert IdentityAgent.get_extension(updated, :plugin_a) == %{a: 1, b: 99, c: 3}
    end
  end

  describe "update_extension/3" do
    test "updates via function" do
      agent =
        IdentityAgent.ensure(create_agent())
        |> IdentityAgent.put_extension(:plugin_a, %{count: 1})

      updated =
        IdentityAgent.update_extension(agent, :plugin_a, fn ext ->
          %{ext | count: ext.count + 1}
        end)

      assert IdentityAgent.get_extension(updated, :plugin_a) == %{count: 2}
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
      assert Map.has_key?(snap, :capabilities)
    end
  end
end
