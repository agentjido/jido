defmodule JidoExampleTest.ThreadPluginTest do
  @moduledoc """
  Example test demonstrating Thread as a default plugin and conversation history patterns.

  This test shows:
  - Every agent gets `Jido.Thread.Plugin` automatically (default singleton plugin)
  - Using `Jido.Thread.Agent` helpers: `ensure/2`, `append/3`, `get/1`, `has_thread?/1`
  - Actions that build conversation history using Thread
  - Disabling the thread plugin with `default_plugins: %{__thread__: false}`
  - The strategy layer auto-tracks instruction_start/instruction_end when thread exists

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent
  alias Jido.AgentServer

  # ===========================================================================
  # ACTIONS: Conversation history via Thread
  # ===========================================================================

  defmodule RecordMessageAction do
    @moduledoc false
    use Jido.Action,
      name: "record_message",
      schema: [
        role: [type: :string, required: true],
        content: [type: :string, required: true]
      ]

    def run(%{role: role, content: content}, context) do
      thread =
        case Map.get(context.state, :__thread__) do
          nil -> Thread.new()
          existing -> existing
        end

      entry = %{kind: :message, payload: %{role: role, content: content}}
      updated_thread = Thread.append(thread, entry)

      {:ok, %{__thread__: updated_thread, last_role: role}}
    end
  end

  defmodule SummarizeAction do
    @moduledoc false
    use Jido.Action,
      name: "summarize",
      schema: []

    def run(_params, context) do
      thread = Map.get(context.state, :__thread__)

      message_count =
        case thread do
          nil -> 0
          t -> length(Thread.filter_by_kind(t, :message))
        end

      {:ok, %{summary: "#{message_count} messages in thread"}}
    end
  end

  # ===========================================================================
  # AGENTS
  # ===========================================================================

  defmodule ChatAgent do
    @moduledoc false
    use Jido.Agent,
      name: "chat_agent",
      description: "Agent with default thread plugin for conversation history",
      schema: [
        last_role: [type: :string, default: nil],
        summary: [type: :string, default: nil]
      ]

    def signal_routes(_ctx) do
      [
        {"record_message", RecordMessageAction},
        {"summarize", SummarizeAction}
      ]
    end
  end

  defmodule StatelessAgent do
    @moduledoc false
    use Jido.Agent,
      name: "stateless_agent",
      description: "Agent with thread plugin explicitly disabled",
      default_plugins: %{__thread__: false},
      schema: [
        value: [type: :integer, default: 0]
      ]
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "thread plugin is a default singleton" do
    test "new agent has no thread until initialized on demand" do
      agent = ChatAgent.new()

      refute ThreadAgent.has_thread?(agent)
    end

    test "ThreadAgent.ensure initializes thread on demand" do
      agent = ChatAgent.new()

      agent = ThreadAgent.ensure(agent, metadata: %{user_id: "u1"})

      assert ThreadAgent.has_thread?(agent)
      thread = ThreadAgent.get(agent)
      assert %Thread{} = thread
      assert thread.metadata == %{user_id: "u1"}
      assert Thread.entry_count(thread) == 0
    end
  end

  describe "action-based thread manipulation" do
    test "action can initialize and append to thread" do
      agent = ChatAgent.new()

      {agent, []} =
        ChatAgent.cmd(agent, {RecordMessageAction, %{role: "user", content: "hello"}})

      assert agent.state.last_role == "user"
      assert ThreadAgent.has_thread?(agent)

      messages = Thread.filter_by_kind(ThreadAgent.get(agent), :message)
      assert length(messages) == 1

      [entry] = messages
      assert entry.kind == :message
      assert entry.payload.role == "user"
      assert entry.payload.content == "hello"
    end

    test "thread accumulates message entries across multiple actions" do
      agent = ChatAgent.new()

      {agent, []} =
        ChatAgent.cmd(agent, {RecordMessageAction, %{role: "user", content: "hi"}})

      {agent, []} =
        ChatAgent.cmd(agent, {RecordMessageAction, %{role: "assistant", content: "hello!"}})

      {agent, []} =
        ChatAgent.cmd(agent, {RecordMessageAction, %{role: "user", content: "how are you?"}})

      messages = Thread.filter_by_kind(ThreadAgent.get(agent), :message)
      assert length(messages) == 3

      roles = Enum.map(messages, & &1.payload.role)
      assert roles == ["user", "assistant", "user"]

      thread = ThreadAgent.get(agent)
      assert Thread.entry_count(thread) > 3

      instruction_starts = Thread.filter_by_kind(thread, :instruction_start)
      assert length(instruction_starts) > 0

      {agent, []} = ChatAgent.cmd(agent, SummarizeAction)
      assert agent.state.summary == "3 messages in thread"
    end
  end

  describe "disabling thread plugin" do
    test "agent with default_plugins: %{__thread__: false} has no thread capability" do
      agent = StatelessAgent.new()

      refute ThreadAgent.has_thread?(agent)
      refute Map.has_key?(agent.state, :__thread__)
    end
  end

  describe "pure cmd/2 thread manipulation with ThreadAgent helpers" do
    test "ThreadAgent.append creates thread and adds entries" do
      agent = ChatAgent.new()

      agent =
        ThreadAgent.append(agent, %{kind: :message, payload: %{role: "system", content: "init"}})

      assert ThreadAgent.has_thread?(agent)
      assert Thread.entry_count(ThreadAgent.get(agent)) == 1

      agent =
        ThreadAgent.append(agent, [
          %{kind: :message, payload: %{role: "user", content: "q1"}},
          %{kind: :message, payload: %{role: "assistant", content: "a1"}}
        ])

      thread = ThreadAgent.get(agent)
      assert Thread.entry_count(thread) == 3

      entries = Thread.to_list(thread)
      contents = Enum.map(entries, & &1.payload.content)
      assert contents == ["init", "q1", "a1"]
    end
  end

  describe "thread via AgentServer" do
    test "thread persists across signals in a running server", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, ChatAgent, id: unique_id("chat"))

      {:ok, _agent} =
        AgentServer.call(
          pid,
          signal("record_message", %{role: "user", content: "first message"})
        )

      {:ok, _agent} =
        AgentServer.call(
          pid,
          signal("record_message", %{role: "assistant", content: "first reply"})
        )

      {:ok, agent} =
        AgentServer.call(pid, signal("summarize"))

      assert agent.state.summary == "2 messages in thread"
    end
  end
end
