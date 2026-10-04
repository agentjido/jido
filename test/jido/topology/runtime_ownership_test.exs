defmodule Jido.Topology.RuntimeOwnershipTest do
  use JidoTest.Case, async: false
  alias Jido.Topology.{Controller, Runtime}
  alias JidoTest.AgentFixtures.CounterAgent

  defmodule StopBarrier do
    use GenServer

    def start_link(observer), do: GenServer.start_link(__MODULE__, observer)

    @impl true
    def init(observer) do
      Process.flag(:trap_exit, true)
      {:ok, observer}
    end

    @impl true
    def terminate(_reason, observer) do
      send(observer, {:gate_branch_draining, self()})

      receive do
        :release -> :ok
      after
        4_000 -> :ok
      end
    end
  end

  defmodule StopPlugin do
    use Jido.Plugin

    @impl true
    def child_spec(_init) do
      observer = :persistent_term.get({__MODULE__, :observer})
      %{id: __MODULE__, start: {StopBarrier, :start_link, [observer]}, shutdown: 5_000}
    end
  end

  test "root replacement waits for an old child Gate to finish shutdown", c do
    :persistent_term.put({StopPlugin, :observer}, self())
    on_exit(fn -> :persistent_term.erase({StopPlugin, :observer}) end)
    id = unique_id("gate_shutdown")
    definition = %{CounterAgent.definition() | plugins: [StopPlugin]}

    options = [
      jido: c.jido,
      id: id,
      topology: %{
        name: "root",
        children: [
          %{
            key: :team,
            topology: %{name: "leaf", agents: [%{key: :counter, definition: definition}]},
            gate: %{commands: [%{type: "counter.add", member: :counter}]}
          }
        ]
      },
      activation: :lazy
    ]

    {:ok, root} = Runtime.start_link(options)
    Process.unlink(root)

    on_exit(fn ->
      if pid = Runtime.whereis_runtime(c.jido, id), do: Supervisor.stop(pid)
    end)

    signal = Jido.Signal.new!("counter.add", %{by: 1, label: "test"}, source: "/test")
    assert {:ok, _} = Runtime.call(c.jido, id, {:child, :team}, signal)
    gate_name = Controller.name(c.jido, id, {:gate_supervisor, "team"})
    old_gate = GenServer.whereis(gate_name)
    old_owner = Runtime.lookup(c.jido, id, :runtime_owner)
    root_monitor = Process.monitor(root)
    gate_monitor = Process.monitor(old_gate)
    Process.exit(root, :kill)
    assert_receive {:DOWN, ^root_monitor, :process, ^root, :killed}, 5_000
    assert_receive {:gate_branch_draining, worker}, 5_000

    try do
      replacement =
        Task.async(fn ->
          with {:ok, pid} <- Runtime.start_link(options) do
            Process.unlink(pid)
            {:ok, pid}
          end
        end)

      eventually(fn ->
        case Process.info(replacement.pid, :monitors) do
          {:monitors, monitors} -> {:process, old_owner} in monitors
          nil -> false
        end
      end)

      assert GenServer.whereis(gate_name) == old_gate
      send(worker, :release)
      assert {:ok, new_root} = Task.await(replacement, 5_000)
      assert_receive {:DOWN, ^gate_monitor, :process, ^old_gate, _}, 5_000
      assert GenServer.whereis(gate_name) != old_gate
      assert :ok = Runtime.await_ready(c.jido, id)
      assert :ok = Supervisor.stop(new_root)
    after
      send(worker, :release)
    end
  end
end
