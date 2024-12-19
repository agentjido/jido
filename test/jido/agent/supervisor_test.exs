# defmodule Jido.Agent.SupervisorTest do
#   use ExUnit.Case, async: true
#   import Mimic
#   require Logger

#   alias Jido.Agent.Supervisor, as: AgentSupervisor
#   alias JidoTest.SimpleAgent

#   setup :set_mimic_global

#   setup do
#     start_supervised!({Phoenix.PubSub, name: TestPubSub})
#     start_supervised!({Registry, keys: :unique, name: Jido.AgentRegistry})
#     start_supervised!({AgentSupervisor, pubsub: TestPubSub})
#     :ok
#   end

#   describe "initialization" do
#     test "starts with no children" do
#       assert [] == AgentSupervisor.which_children()
#     end
#   end

#   describe "agent management" do
#     setup do
#       agent = SimpleAgent.new("test_agent")
#       %{agent: agent}
#     end

#     test "starts an agent worker", %{agent: agent} do
#       assert {:ok, pid} = AgentSupervisor.start_agent(agent)
#       assert Process.alive?(pid)
#       assert [{:undefined, ^pid, :worker, [Jido.Agent.Worker]}] = AgentSupervisor.which_children()
#     end

#     test "starts an agent with custom name", %{agent: agent} do
#       custom_name = "custom_agent_name"
#       agent = %{agent | id: custom_name}

#       Logger.debug("Starting agent with custom name: #{custom_name}")
#       Logger.debug("Agent struct: #{inspect(agent)}")

#       assert {:ok, pid} = AgentSupervisor.start_agent(agent, name: custom_name)
#       Logger.debug("Agent started with pid: #{inspect(pid)}")

#       # Add small delay to ensure registration is complete
#       Process.sleep(100)

#       # Log registry state before lookup
#       registry_entries =
#         Registry.select(Jido.AgentRegistry, [
#           {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
#         ])

#       Logger.debug("Registry entries before lookup: #{inspect(registry_entries)}")

#       assert {:ok, ^pid} = AgentSupervisor.find_agent(custom_name)
#     end

#     test "terminates agent worker", %{agent: agent} do
#       {:ok, pid} = AgentSupervisor.start_agent(agent)
#       assert :ok = AgentSupervisor.terminate_child(pid)
#       refute Process.alive?(pid)
#       assert [] = AgentSupervisor.which_children()
#     end

#     # test "handles agent worker crash", %{agent: agent} do
#     #   {:ok, pid} = AgentSupervisor.start_agent(agent)
#     #   ref = Process.monitor(pid)
#     #   Process.exit(pid, :kill)

#     #   assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
#     #   Process.sleep(100)
#     #   # Since restart: :transient, should not restart
#     #   assert [] = AgentSupervisor.which_children()
#     # end
#   end

#   describe "child process management" do
#     test "starts a generic child process" do
#       defmodule TestWorker do
#         use GenServer
#         def start_link(args), do: GenServer.start_link(__MODULE__, args)
#         def init(args), do: {:ok, args}
#       end

#       assert {:ok, pid} = AgentSupervisor.start_child(TestWorker, %{test: true})
#       assert Process.alive?(pid)
#       assert [{:undefined, ^pid, :worker, [TestWorker]}] = AgentSupervisor.which_children()
#     end

#     test "handles invalid child specs" do
#       assert {:error, _} = AgentSupervisor.start_child(InvalidModule, [])
#     end

#     test "terminates child process" do
#       {:ok, pid} = AgentSupervisor.start_child(Task, fn -> Process.sleep(:infinity) end)
#       assert :ok = AgentSupervisor.terminate_child(pid)
#       refute Process.alive?(pid)
#     end
#   end

#   describe "process registration" do
#     setup do
#       agent = SimpleAgent.new("test_agent")
#       %{agent: agent}
#     end

#     test "registers agent process", %{agent: agent} do
#       {:ok, pid} = AgentSupervisor.start_agent(agent)
#       assert {:ok, ^pid} = AgentSupervisor.find_agent(agent.id)
#     end

#     test "handles lookup of non-existent agent" do
#       assert {:error, :not_found} = AgentSupervisor.find_agent("nonexistent")
#     end

#     test "handles multiple agents", %{agent: agent} do
#       agent2 = SimpleAgent.new("test_agent_2")

#       {:ok, pid1} = AgentSupervisor.start_agent(agent)
#       {:ok, pid2} = AgentSupervisor.start_agent(agent2)

#       assert {:ok, ^pid1} = AgentSupervisor.find_agent(agent.id)
#       assert {:ok, ^pid2} = AgentSupervisor.find_agent(agent2.id)
#     end
#   end

#   describe "supervisor behavior" do
#     setup do
#       # Start a fresh supervisor for isolation
#       sup_name = String.to_atom("test_sup_#{System.unique_integer([:positive, :monotonic])}")

#       # Stop any existing supervisor with this name
#       if Process.whereis(sup_name) do
#         Supervisor.stop(sup_name)
#       end

#       # Start the supervisor directly instead of using start_supervised
#       {:ok, pid} = AgentSupervisor.start_link(name: sup_name, pubsub: TestPubSub)

#       on_exit(fn ->
#         if Process.alive?(pid) do
#           Supervisor.stop(sup_name)
#         end
#       end)

#       %{supervisor: sup_name, supervisor_pid: pid}
#     end

#     # test "respects max restart limits", %{supervisor: sup} do
#     #   # Define a worker that always crashes
#     #   defmodule CrashingWorker do
#     #     use GenServer
#     #     def start_link(_), do: GenServer.start_link(__MODULE__, [])
#     #     def init(_), do: {:ok, nil}
#     #     def handle_info(:crash, _), do: raise("crash")
#     #   end

#     #   # Start and crash workers quickly within the 1 second window
#     #   for _ <- 1..3 do
#     #     {:ok, pid} = AgentSupervisor.start_child(CrashingWorker, [])
#     #     ref = Process.monitor(pid)
#     #     send(pid, :crash)
#     #     # Wait for the crash
#     #     assert_receive {:DOWN, ^ref, :process, ^pid, {%RuntimeError{message: "crash"}, _}}, 500
#     #   end

#     #   # Small delay to ensure supervisor processes the crashes
#     #   Process.sleep(100)

#     #   # Try to start another worker - should be rejected due to max restarts
#     #   assert match?({:error, {:max_children, _}}, AgentSupervisor.start_child(CrashingWorker, []))
#     # end

#     test "maintains child process isolation", %{supervisor: sup} do
#       defmodule Worker do
#         use GenServer
#         def start_link(_), do: GenServer.start_link(__MODULE__, [])
#         def init(_), do: {:ok, nil}
#       end

#       {:ok, pid1} = AgentSupervisor.start_child(Worker, [])
#       {:ok, pid2} = AgentSupervisor.start_child(Worker, [])

#       # Killing one worker shouldn't affect the other
#       Process.exit(pid1, :kill)
#       Process.sleep(100)
#       refute Process.alive?(pid1)
#       assert Process.alive?(pid2)
#     end
#   end

#   describe "telemetry" do
#     setup do
#       agent = SimpleAgent.new("test_agent")

#       :telemetry.attach(
#         "test-handler",
#         [:jido, :agent, :supervisor, :agent, :start],
#         fn event, measurements, metadata, _config ->
#           send(self(), {:telemetry, event, measurements, metadata})
#         end,
#         nil
#       )

#       on_exit(fn ->
#         :telemetry.detach("test-handler")
#       end)

#       %{agent: agent}
#     end

#     test "emits telemetry on agent start", %{agent: agent} do
#       {:ok, _pid} = AgentSupervisor.start_agent(agent)

#       assert_receive {:telemetry, [:jido, :agent, :supervisor, :agent, :start], %{duration: _},
#                       %{agent_id: "test_agent", result: {:ok, _}}}
#     end
#   end
# end
