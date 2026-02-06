defmodule JidoTest.Identity.ProfileTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Identity
  alias Jido.Identity.Agent, as: IdentityAgent
  alias Jido.Identity.Profile

  defp create_agent do
    %Agent{id: "test-agent-1", state: %{}}
  end

  describe "age/1" do
    test "returns nil when no identity" do
      agent = create_agent()
      assert Profile.age(agent) == nil
    end

    test "returns age when present" do
      identity = Identity.new(profile: %{age: 7})
      agent = IdentityAgent.put(create_agent(), identity)
      assert Profile.age(agent) == 7
    end
  end

  describe "get/3" do
    test "returns default when no identity" do
      agent = create_agent()
      assert Profile.get(agent, :age, :fallback) == :fallback
    end

    test "returns key value when present" do
      identity = Identity.new(profile: %{age: 3, origin: "lab"})
      agent = IdentityAgent.put(create_agent(), identity)
      assert Profile.get(agent, :origin) == "lab"
    end
  end

  describe "put/3" do
    test "sets key in profile" do
      agent = IdentityAgent.ensure(create_agent())
      updated = Profile.put(agent, :origin, "cloud")
      assert Profile.get(updated, :origin) == "cloud"
    end

    test "bumps rev" do
      agent = IdentityAgent.ensure(create_agent())
      rev_before = IdentityAgent.get(agent).rev
      updated = Profile.put(agent, :origin, "cloud")
      assert IdentityAgent.get(updated).rev > rev_before
    end
  end
end
