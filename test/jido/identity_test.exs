defmodule JidoTest.IdentityTest do
  use ExUnit.Case, async: true

  alias Jido.Identity

  describe "new/1" do
    test "creates identity with default values" do
      identity = Identity.new()

      assert identity.rev == 0
      assert identity.profile == %{age: nil}
    end

    test "accepts custom profile" do
      identity = Identity.new(profile: %{age: 5, origin: "lab"})

      assert identity.profile == %{age: 5, origin: "lab"}
    end

    test "sets created_at and updated_at timestamps" do
      now = 1_000_000
      identity = Identity.new(now: now)

      assert identity.created_at == now
      assert identity.updated_at == now
    end
  end

  describe "evolve/2" do
    test "increments rev by 1" do
      identity = Identity.new() |> Identity.evolve()

      assert identity.rev == 1
    end

    test "increments age by years" do
      identity = Identity.new(profile: %{age: 0}) |> Identity.evolve(years: 3)

      assert identity.profile[:age] == 3
    end

    test "increments age by days" do
      identity = Identity.new(profile: %{age: 0}) |> Identity.evolve(days: 730)

      assert identity.profile[:age] == 2
    end

    test "increments age by combined years and days" do
      identity = Identity.new(profile: %{age: 0}) |> Identity.evolve(years: 1, days: 365)

      assert identity.profile[:age] == 2
    end

    test "handles nil age" do
      identity = Identity.new() |> Identity.evolve(years: 5)

      assert identity.profile[:age] == 5
    end

    test "updates updated_at timestamp" do
      identity = Identity.new(now: 1_000) |> Identity.evolve(now: 2_000)

      assert identity.created_at == 1_000
      assert identity.updated_at == 2_000
    end

    test "preserves other profile keys" do
      identity = Identity.new(profile: %{age: 0, origin: "lab"}) |> Identity.evolve(years: 1)

      assert identity.profile[:origin] == "lab"
    end
  end

  describe "snapshot/1" do
    test "returns profile" do
      identity = Identity.new()
      snap = Identity.snapshot(identity)

      assert Map.keys(snap) == [:profile]
    end

    test "filters profile to only age, generation, origin keys" do
      identity = Identity.new(profile: %{age: 5, generation: 2, origin: "lab", secret: "x"})
      snap = Identity.snapshot(identity)

      assert snap.profile == %{age: 5, generation: 2, origin: "lab"}
    end
  end
end
