defmodule JidoTest.Identity.Actions.EvolveTest do
  use ExUnit.Case, async: true

  alias Jido.Identity
  alias Jido.Identity.Actions.Evolve

  describe "run/2" do
    test "initializes identity when missing" do
      assert {:ok, %{__identity__: evolved}} = Evolve.run(%{days: 0, years: 0}, %{state: %{}})
      assert evolved.profile[:age] == 0
    end

    test "evolves identity by years" do
      identity = Identity.new()
      ctx = %{state: %{__identity__: identity}}

      assert {:ok, %{__identity__: evolved}} = Evolve.run(%{days: 0, years: 5}, ctx)
      assert evolved.profile[:age] == 5
    end

    test "evolves identity by days" do
      identity = Identity.new()
      ctx = %{state: %{__identity__: identity}}

      assert {:ok, %{__identity__: evolved}} = Evolve.run(%{days: 730, years: 0}, ctx)
      assert evolved.profile[:age] == 2
    end

    test "evolves identity by combined years and days" do
      identity = Identity.new()
      ctx = %{state: %{__identity__: identity}}

      assert {:ok, %{__identity__: evolved}} = Evolve.run(%{days: 365, years: 3}, ctx)
      assert evolved.profile[:age] == 4
    end

    test "bumps rev on evolve" do
      identity = Identity.new()
      ctx = %{state: %{__identity__: identity}}

      assert identity.rev == 0
      assert {:ok, %{__identity__: evolved}} = Evolve.run(%{days: 0, years: 1}, ctx)
      assert evolved.rev == 1
    end
  end
end
