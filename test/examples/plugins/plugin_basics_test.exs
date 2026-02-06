defmodule JidoExampleTest.PluginBasicsTest do
  @moduledoc """
  Example test demonstrating how to write and use a custom Jido plugin.

  This test shows:
  - How to create a plugin with `use Jido.Plugin`
  - Plugin `mount/2` callback for custom initialization
  - Plugin `signal_routes/1` callback for routing signals to actions
  - An agent that uses plugins via `plugins: [MyPlugin]` or `plugins: [{MyPlugin, config}]`
  - Accessing plugin state via `agent.state.state_key`
  - Pure `cmd/2` with plugin-provided actions

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.AgentServer
  alias Jido.Signal

  # ===========================================================================
  # ACTIONS: Note management operations
  # ===========================================================================

  defmodule AddNoteAction do
    @moduledoc false
    use Jido.Action,
      name: "add_note",
      schema: [
        text: [type: :string, required: true]
      ]

    def run(%{text: text}, context) do
      notes = get_in(context.state, [:notes, :entries]) || []
      note = %{text: text, added_at: DateTime.utc_now()}
      {:ok, %{notes: %{entries: [note | notes]}}}
    end
  end

  defmodule ClearNotesAction do
    @moduledoc false
    use Jido.Action,
      name: "clear_notes",
      schema: []

    def run(_params, _context) do
      {:ok, %{notes: %{entries: []}}}
    end
  end

  # ===========================================================================
  # PLUGIN: NotesPlugin with mount, signal_routes, and Zoi schema
  # ===========================================================================

  defmodule NotesPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "notes_plugin",
      state_key: :notes,
      actions: [
        JidoExampleTest.PluginBasicsTest.AddNoteAction,
        JidoExampleTest.PluginBasicsTest.ClearNotesAction
      ],
      description: "Manages a list of notes",
      schema:
        Zoi.object(%{
          entries: Zoi.list(Zoi.any()) |> Zoi.default([])
        }),
      signal_patterns: ["notes.*"]

    @impl Jido.Plugin
    def mount(_agent, config) do
      label = Map.get(config, :label, "default")
      {:ok, %{label: label}}
    end

    @impl Jido.Plugin
    def signal_routes(_config) do
      [
        {"notes.add", JidoExampleTest.PluginBasicsTest.AddNoteAction},
        {"notes.clear", JidoExampleTest.PluginBasicsTest.ClearNotesAction}
      ]
    end
  end

  # ===========================================================================
  # AGENTS: Using the NotesPlugin
  # ===========================================================================

  defmodule NotesAgent do
    @moduledoc false
    use Jido.Agent,
      name: "notes_agent",
      plugins: [JidoExampleTest.PluginBasicsTest.NotesPlugin]
  end

  defmodule ConfiguredNotesAgent do
    @moduledoc false
    use Jido.Agent,
      name: "configured_notes_agent",
      plugins: [{JidoExampleTest.PluginBasicsTest.NotesPlugin, %{label: "work"}}]
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "plugin initialization" do
    test "agent created with plugin has plugin state initialized" do
      agent = NotesAgent.new()

      assert agent.state.notes.entries == []
      assert agent.state.notes.label == "default"
    end

    test "plugin with config passed at agent definition time" do
      agent = ConfiguredNotesAgent.new()

      assert agent.state.notes.entries == []
      assert agent.state.notes.label == "work"
    end
  end

  describe "plugin signal routing" do
    test "plugin signal route processes signal correctly via AgentServer", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, NotesAgent, id: unique_id("notes"))

      signal = Signal.new!("notes.add", %{text: "hello world"}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert length(agent.state.notes.entries) == 1
      [note] = agent.state.notes.entries
      assert note.text == "hello world"
    end

    test "plugin state is updated across multiple signals", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, NotesAgent, id: unique_id("notes"))

      {:ok, _} =
        AgentServer.call(pid, Signal.new!("notes.add", %{text: "first"}, source: "/test"))

      {:ok, _} =
        AgentServer.call(pid, Signal.new!("notes.add", %{text: "second"}, source: "/test"))

      {:ok, state} = AgentServer.state(pid)
      entries = state.agent.state.notes.entries

      assert length(entries) == 2
      texts = Enum.map(entries, & &1.text)
      assert "first" in texts
      assert "second" in texts

      {:ok, agent} = AgentServer.call(pid, Signal.new!("notes.clear", %{}, source: "/test"))
      assert agent.state.notes.entries == []
    end
  end

  describe "pure cmd/2 with plugin action" do
    test "cmd/2 updates plugin state directly" do
      agent = NotesAgent.new()

      {agent, []} = NotesAgent.cmd(agent, {AddNoteAction, %{text: "from cmd"}})

      assert length(agent.state.notes.entries) == 1
      [note] = agent.state.notes.entries
      assert note.text == "from cmd"
    end
  end
end
