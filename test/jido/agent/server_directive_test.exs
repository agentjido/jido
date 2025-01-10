# defmodule Jido.Agent.Server.DirectiveTest do
#   use ExUnit.Case, async: true
#   alias Jido.Agent.Server.{Directive, State}
#   alias JidoTest.TestAgents.BasicAgent
#   alias Jido.Error

#   alias Jido.Agent.Directive.{
#     SpawnDirective,
#     KillDirective,
#     PublishDirective,
#     SubscribeDirective,
#     UnsubscribeDirective
#   }

#   # Helper to compare Error structs ignoring stacktrace
#   defp assert_error_match(actual, expected) do
#     assert %Error{} = actual
#     assert actual.type == expected.type
#     assert actual.message == expected.message
#     assert actual.details == expected.details
#   end

#   setup do
#     {:ok, supervisor} = start_supervised(DynamicSupervisor)
#     agent = BasicAgent.new("test")
#     {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})

#     state = %State{
#       agent: agent,
#       child_supervisor: supervisor,
#       pubsub: TestPubSub,
#       topic: "test_topic",
#       status: :idle,
#       pending_signals: :queue.new(),
#       subscriptions: []
#     }

#     {:ok, state: state}
#   end

#   describe "process management directives" do
#     test "spawn creates a new child process", %{state: state} do
#       task = fn -> Process.sleep(1000) end
#       directive = %SpawnDirective{module: Task, args: task}
#       {:ok, new_state} = Directive.execute(state, directive)
#       assert state == new_state
#     end

#     test "kill terminates a specific process", %{state: state} do
#       task = fn -> Process.sleep(1000) end
#       spawn_directive = %SpawnDirective{module: Task, args: task}
#       {:ok, state} = Directive.execute(state, spawn_directive)

#       # Get the PID from the state's child processes
#       pid = DynamicSupervisor.which_children(state.child_supervisor) |> hd() |> elem(1)
#       assert Process.alive?(pid)

#       kill_directive = %KillDirective{pid: pid}
#       {:ok, new_state} = Directive.execute(state, kill_directive)
#       refute Process.alive?(pid)
#       assert state == new_state
#     end

#     test "kill returns error for non-existent process", %{state: state} do
#       non_existent_pid = spawn(fn -> :ok end)
#       Process.exit(non_existent_pid, :kill)

#       directive = %KillDirective{pid: non_existent_pid}
#       {:error, error} = Directive.execute(state, directive)

#       assert_error_match(error, %Error{
#         type: :execution_error,
#         message: "Process not found",
#         details: %{pid: non_existent_pid}
#       })
#     end
#   end

#   describe "pubsub directives" do
#     test "broadcast sends message to topic", %{state: state} do
#       Phoenix.PubSub.subscribe(TestPubSub, "test_topic")
#       directive = %PublishDirective{topic: "test_topic", message: "hello"}
#       {:ok, new_state} = Directive.execute(state, directive)
#       assert state == new_state
#       assert_receive "hello"
#     end

#     test "subscribe adds subscription to state", %{state: state} do
#       directive = %SubscribeDirective{topic: "test_topic"}
#       {:ok, new_state} = Directive.execute(state, directive)
#       assert "test_topic" in new_state.subscriptions
#     end

#     test "unsubscribe removes subscription from state", %{state: state} do
#       # First subscribe
#       subscribe_directive = %SubscribeDirective{topic: "test_topic"}
#       {:ok, state_with_sub} = Directive.execute(state, subscribe_directive)
#       assert "test_topic" in state_with_sub.subscriptions

#       # Then unsubscribe
#       unsubscribe_directive = %UnsubscribeDirective{topic: "test_topic"}
#       {:ok, final_state} = Directive.execute(state_with_sub, unsubscribe_directive)
#       refute "test_topic" in final_state.subscriptions
#     end
#   end

#   describe "error handling" do
#     test "returns error for invalid directive", %{state: state} do
#       {:error, error} = Directive.execute(state, :invalid_directive)

#       assert_error_match(error, %Error{
#         type: :validation_error,
#         message: "Invalid directive",
#         details: %{directive: :invalid_directive}
#       })
#     end

#     test "handles pubsub errors", %{state: state} do
#       # Test with nil pubsub
#       state_without_pubsub = %{state | pubsub: nil}
#       directive = %PublishDirective{topic: "test_topic", message: "hello"}
#       {:error, error} = Directive.execute(state_without_pubsub, directive)

#       assert_error_match(error, %Error{
#         type: :execution_error,
#         message: "PubSub not configured",
#         details: %{}
#       })
#     end
#   end
# end
