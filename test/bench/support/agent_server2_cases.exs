defmodule JidoCoreBench.AgentServer2Cases do
  @moduledoc false
  alias Jido.AgentServer2, as: Server
  alias JidoCoreBench.Fixtures, as: F

  defmodule Resource do
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init)
    def init(init), do: {:ok, init}
  end

  defmodule Tree do
    use Supervisor
    def start_link(init), do: Supervisor.start_link(__MODULE__, init)

    def init(init) do
      Supervisor.init(
        for(i <- 1..init.options[:width], do: %{id: i, start: {Resource, :start_link, [init]}}),
        strategy: :one_for_one
      )
    end
  end

  defmodule ResourcePlugin do
    use Jido.Plugin

    def child_spec(init) do
      if init.options[:width],
        do: %{id: __MODULE__, start: {Tree, :start_link, [init]}, type: :supervisor},
        else: %{id: __MODULE__, start: {Resource, :start_link, [init]}}
    end
  end

  def workloads do
    for mode <- [:turn, :worker_plugin, :tree_plugin, :family] do
      plugins =
        case mode do
          :worker_plugin -> [ResourcePlugin]
          :tree_plugin -> [{ResourcePlugin, width: 3}]
          _ -> []
        end

      F.checked(
        "agent_server2/#{mode}",
        fn context ->
          a = F.agent(1, nil, JidoCoreBench.Add, plugins)
          # Start from the measured caller so spawn tracing includes the tree.
          # The instance load profile separately uses its DynamicSupervisor.
          previous_trap = Process.flag(:trap_exit, true)
          {:ok, root} = Server.Supervisor.start_link(agent: a, jido: JidoCoreBench)
          pid = Server.Supervisor.worker(root)
          :ok = Server.await_ready(pid)

          family =
            if mode == :family do
              {:ok, owned} = Server.spawn_child(pid, %{a | id: "owned"}, :owned)

              {:ok, independent} =
                Server.spawn_child(pid, %{a | id: "independent"}, :independent,
                  placement: :independent,
                  on_parent_exit: :continue
                )

              %{owned: Server.activation(owned), independent: independent}
            end

          %{pid: pid, family: family, context: context, previous_trap: previous_trap}
        end,
        fn prepared ->
          if mode == :family do
            :ok = Server.stop(prepared.pid)
            {Process.alive?(prepared.family.owned), Server.alive?(prepared.family.independent)}
          else
            Server.call(prepared.pid, F.signal(), context: prepared.context)
          end
        end,
        fn result ->
          if mode == :family,
            do: F.equal!(result, {false, true}),
            else: F.candidate!(result, 1, nil)
        end
      )
      |> Map.put(:cleanup, fn prepared ->
        if Server.alive?(prepared.pid), do: Server.stop(prepared.pid)
        if prepared.family, do: Server.stop(prepared.family.independent)
        Process.flag(:trap_exit, prepared.previous_trap)
        :ok
      end)
    end
  end

  def load(jido, count, opts \\ []) when count > 0 do
    definition = F.definition()
    prefix = "load-#{System.unique_integer([:positive])}"
    baseline = snapshot()
    started = System.monotonic_time(:microsecond)

    agents =
      for i <- 1..count do
        plugins =
          case rem(i - 1, 10) do
            5 -> [JidoCoreBench.PreparePlugin]
            6 -> [ResourcePlugin]
            7 -> [{ResourcePlugin, width: 1}]
            8 -> [{ResourcePlugin, width: 3}]
            9 -> [{ResourcePlugin, width: 5}]
            _ -> []
          end

        a = Jido.Agent.instantiate!(%{definition | plugins: plugins}, id: "#{prefix}-#{i}")
        {:ok, worker} = Server.start(Keyword.merge([agent: a, jido: jido], opts))
        {a.id, worker, Server.activation(worker)}
      end

    for {_, worker, _} <- agents do
      :ok = Server.await_ready(worker)
      # Exercise retained control records and owner monitor release before the
      # memory sample. These are runtime data, not checkpoint state.
      :ok = Server.attach(worker)
      :ok = Server.touch(worker)
      :ok = Server.quiesce(worker)
      :ok = Server.resume(worker)
      :ok = Server.detach(worker)
    end

    startup_us = System.monotonic_time(:microsecond) - started

    try do
      pids = Enum.flat_map(agents, fn {_, _, root} -> tree(root) end)
      for pid <- pids, do: :erlang.garbage_collect(pid)
      idle_bytes = Enum.sum(for pid <- pids, do: elem(Process.info(pid, :memory), 1))
      owned = MapSet.new(pids)

      ets_bytes =
        :ets.all()
        |> Enum.filter(&MapSet.member?(owned, :ets.info(&1, :owner)))
        |> Enum.map(&(:ets.info(&1, :memory) * :erlang.system_info(:wordsize)))
        |> Enum.sum()

      idle = snapshot()
      turn_started = System.monotonic_time(:microsecond)
      # Large transient caller input must not remain in saved runtime data.
      for {_, worker, _} <- Enum.take(agents, 20) do
        {:ok, _, []} =
          Server.call(worker, F.signal(),
            context: %{temporary_payload: :binary.copy(<<42>>, 131_072)}
          )

        :erlang.garbage_collect(worker)
        {:binary, binaries} = Process.info(worker, :binary)

        if Enum.any?(binaries, fn {_, size, _} -> size >= 131_072 end),
          do: raise("Agent retained caller input")
      end

      turn_us = System.monotonic_time(:microsecond) - turn_started
      recovery_started = System.monotonic_time(:microsecond)

      for {id, worker, _root} <- Enum.take(agents, 5) do
        monitor = Process.monitor(worker)
        Process.exit(worker, :kill)
        receive do: ({:DOWN, ^monitor, :process, ^worker, _} -> :ok)

        replacement =
          wait(fn ->
            case Server.whereis(jido, id) do
              pid when is_pid(pid) and pid != worker -> pid
              _ -> nil
            end
          end)

        :ok = Server.await_ready(replacement)
        F.equal!(Server.agent(replacement).state.count, 1)
        F.equal!(Server.status(replacement).state_version, 1)
      end

      recovery_us = System.monotonic_time(:microsecond) - recovery_started

      restores =
        if Keyword.get(opts, :persistence) not in [nil, false] do
          for {id, _, _} <- Enum.take(agents, 5) do
            current = Server.whereis(jido, id)
            agent = Server.agent(current)
            :ok = Server.hibernate(current)

            {:ok, restored} =
              Server.start(
                Keyword.merge(opts, agent: agent, jido: jido, persistence_mode: :restore)
              )

            :ok = Server.await_ready(restored)
            F.equal!(Server.agent(restored).state.count, 1)
            F.equal!(Server.status(restored).state_version, 1)
          end

          min(count, 5)
        else
          0
        end

      stop_started = System.monotonic_time(:microsecond)

      for {id, _worker, root} <- agents do
        :ok = Server.stop(Server.whereis(jido, id))
        if Process.alive?(root), do: raise("activation survived stop")
      end

      stop_us = System.monotonic_time(:microsecond) - stop_started
      :ok = clean(jido)

      %{
        agents: count,
        plugin_agents: div(count, 10) * 5,
        startup_us: startup_us,
        stop_us: stop_us,
        turns: min(count, 20),
        turn_us: turn_us,
        recoveries: min(count, 5),
        recovery_us: recovery_us,
        control_cycles: count,
        hibernations: restores,
        durable_restores: restores,
        activation_processes: length(pids),
        idle_process_bytes: idle_bytes,
        idle_ets_bytes: ets_bytes,
        idle: idle,
        before: baseline
      }
    after
      for {id, _, _} <- agents do
        if worker = Server.whereis(jido, id), do: Server.stop(worker)
      end
    end
  end

  def clean(jido) do
    wait(fn ->
      DynamicSupervisor.which_children(Jido.agent_supervisor_name(jido)) == [] and
        DynamicSupervisor.which_children(
          Module.concat(Jido.exec_runner_name(jido), WorkerSupervisor)
        ) == [] and
        Task.Supervisor.children(Module.concat(Jido.exec_runner_name(jido), TaskSupervisor)) == [] and
        Registry.count(Jido.registry_name(jido)) == 0
    end)

    wait(fn ->
      guard = :sys.get_state(Jido.registration_guard_name(jido))
      map_size(guard.claims) == 0 and map_size(guard.refs) == 0
    end)

    # Measure retained memory after collection in this isolated instance only.
    for pid <- tree(Process.whereis(jido)), do: :erlang.garbage_collect(pid)
    :ok
  end

  def snapshot do
    %{
      processes: :erlang.system_info(:process_count),
      ets_tables: length(:ets.all()),
      process_bytes: :erlang.memory(:processes_used),
      binary_bytes: :erlang.memory(:binary)
    }
  end

  defp tree(root) do
    [
      root
      | Enum.flat_map(Supervisor.which_children(root), fn
          {_, pid, :supervisor, _} when is_pid(pid) -> tree(pid)
          {_, pid, _, _} when is_pid(pid) -> [pid]
          _ -> []
        end)
    ]
  end

  defp wait(fun), do: wait(fun, System.monotonic_time(:millisecond) + 10_000)

  defp wait(fun, deadline) do
    case fun.() do
      value when value not in [nil, false] ->
        value

      _ ->
        if System.monotonic_time(:millisecond) >= deadline,
          do: raise("load cleanup or recovery did not settle")

        receive do
        after
          1 -> wait(fun, deadline)
        end
    end
  end
end
