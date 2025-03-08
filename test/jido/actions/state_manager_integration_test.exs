defmodule Jido.Actions.StateManagerIntegrationTest do
  use JidoTest.Case, async: true
  alias JidoTest.TestAgents.FullFeaturedAgent
  alias Jido.Actions.StateManager.{Set, Get, Update, Delete}

  @moduletag :capture_log

  describe "State Management Integration" do
    setup do
      agent = FullFeaturedAgent.new()
      {:ok, agent: agent}
    end

    # Helper function to make cmd calls more concise
    defp run_cmd(agent, action, params, opts \\ []) do
      FullFeaturedAgent.cmd(
        agent,
        {action, params},
        %{},
        Keyword.merge([runner: Jido.Runner.Chain, apply_state: true], opts)
      )
    end

    test "performs basic state operations through agent", %{agent: agent} do
      # Set initial state
      {:ok, agent, []} = run_cmd(agent, Set, %{path: [:settings, :theme], value: "dark"})
      assert get_in(agent.state, [:settings, :theme]) == "dark"

      # Get the value
      {:ok, agent, []} = run_cmd(agent, Get, %{path: [:settings, :theme]})
      assert agent.result.value == "dark"

      # Update the value
      {:ok, agent, []} = run_cmd(agent, Update, %{path: [:settings, :theme], value: "DARK"})
      assert get_in(agent.state, [:settings, :theme]) == "DARK"

      # Delete the value
      {:ok, agent, []} = run_cmd(agent, Delete, %{path: [:settings, :theme]})
      assert get_in(agent.state, [:settings, :theme]) == nil
    end

    test "handles nested state operations", %{agent: agent} do
      # Set deeply nested state
      {:ok, agent, []} =
        run_cmd(
          agent,
          Set,
          %{path: [:user, :preferences, :notifications, :email], value: true}
        )

      assert get_in(agent.state, [:user, :preferences, :notifications, :email]) == true

      # Update nested value
      {:ok, agent, []} =
        run_cmd(
          agent,
          Update,
          %{path: [:user, :preferences, :notifications, :email], value: false}
        )

      assert get_in(agent.state, [:user, :preferences, :notifications, :email]) == false

      # Delete nested value
      {:ok, agent, []} =
        run_cmd(
          agent,
          Delete,
          %{path: [:user, :preferences, :notifications, :email]}
        )

      assert get_in(agent.state, [:user, :preferences, :notifications, :email]) == nil
    end

    test "handles multiple operations in sequence", %{agent: agent} do
      # Set multiple values
      {:ok, agent, []} =
        run_cmd(
          agent,
          Set,
          %{path: [:counter], value: 0}
        )

      {:ok, agent, []} =
        run_cmd(
          agent,
          Set,
          %{path: [:settings, :theme], value: "light"}
        )

      {:ok, agent, []} =
        run_cmd(
          agent,
          Set,
          %{path: [:user, :name], value: "Alice"}
        )

      assert get_in(agent.state, [:counter]) == 0
      assert get_in(agent.state, [:settings, :theme]) == "light"
      assert get_in(agent.state, [:user, :name]) == "Alice"

      # Update multiple values
      {:ok, agent, []} =
        run_cmd(
          agent,
          Update,
          %{path: [:counter], value: 1}
        )

      {:ok, agent, []} =
        run_cmd(
          agent,
          Update,
          %{path: [:settings, :theme], value: "LIGHT"}
        )

      {:ok, agent, []} =
        run_cmd(
          agent,
          Update,
          %{path: [:user, :name], value: "Alice Smith"}
        )

      assert get_in(agent.state, [:counter]) == 1
      assert get_in(agent.state, [:settings, :theme]) == "LIGHT"
      assert get_in(agent.state, [:user, :name]) == "Alice Smith"

      # Delete multiple values
      {:ok, agent, []} =
        run_cmd(
          agent,
          Delete,
          %{path: [:counter]}
        )

      {:ok, agent, []} =
        run_cmd(
          agent,
          Delete,
          %{path: [:settings, :theme]}
        )

      {:ok, agent, []} =
        run_cmd(
          agent,
          Delete,
          %{path: [:user, :name]}
        )

      assert get_in(agent.state, [:counter]) == nil
      assert get_in(agent.state, [:settings, :theme]) == nil
      assert get_in(agent.state, [:user, :name]) == nil
    end

    test "handles non-existent paths gracefully", %{agent: agent} do
      # Try to get non-existent path
      {:ok, agent, []} =
        run_cmd(
          agent,
          Get,
          %{path: [:nonexistent]}
        )

      assert agent.result.value == nil

      # Try to update non-existent path
      {:ok, agent, []} =
        run_cmd(
          agent,
          Update,
          %{path: [:nonexistent], value: 1}
        )

      assert get_in(agent.state, [:nonexistent]) == 1

      # Try to delete non-existent path
      {:ok, agent, []} =
        run_cmd(
          agent,
          Delete,
          %{path: [:another_nonexistent]}
        )

      assert get_in(agent.state, [:another_nonexistent]) == nil
    end

    test "maintains state integrity during operations", %{agent: agent} do
      # Set initial state
      {:ok, agent, []} =
        run_cmd(
          agent,
          Set,
          %{path: [:data, :items], value: ["one", "two", "three"]}
        )

      assert get_in(agent.state, [:data, :items]) == ["one", "two", "three"]

      # Update specific item
      {:ok, agent, []} =
        run_cmd(
          agent,
          Update,
          %{path: [:data, :items], value: ["one", "TWO", "three"]}
        )

      assert get_in(agent.state, [:data, :items]) == ["one", "TWO", "three"]

      # Delete specific item
      {:ok, agent, []} =
        run_cmd(
          agent,
          Update,
          %{path: [:data, :items], value: ["one", "three"]}
        )

      assert get_in(agent.state, [:data, :items]) == ["one", "three"]
    end
  end
end
