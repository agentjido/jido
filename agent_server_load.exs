# Run from jido: mix run --no-start agent_server_load.exs 10 1000 10000
# Add --persistent to measure required saves and new activation restores with ETS.
Code.require_file("test/bench/support/fixtures.exs", __DIR__)
Code.require_file("test/bench/support/agent_server_cases.exs", __DIR__)

defmodule AgentServerLoad do
  alias JidoCoreBench.AgentServerCases, as: Load

  def run do
    {:ok, _} = Application.ensure_all_started(:jido)
    persistent? = "--persistent" in System.argv()
    table = :agent_server_load_durable_records
    adapter = {Jido.Persistence.ETS, table: :agent_server_load_durable}
    opts = if persistent?, do: [persistence: adapter], else: []
    {:ok, instance} = Jido.start_link(name: __MODULE__, namespace: "jido/load/server")

    try do
      # Load all Plugin shapes and execution paths before recording the baseline.
      Load.load(__MODULE__, 10, opts)
      if persistent?, do: :ets.delete_all_objects(table)
      :erlang.garbage_collect()
      baseline = Load.snapshot()
      baseline_pids = MapSet.new(Process.list())
      baseline_tables = MapSet.new(:ets.all())

      sizes =
        case System.argv() -- ["--persistent"] do
          [] -> [10, 1000]
          args -> Enum.map(args, &String.to_integer/1)
        end

      if Enum.any?(sizes, &(&1 < 10 or &1 > 10000 or rem(&1, 10) != 0)),
        do: raise("use multiples of 10, from 10 through 10000")

      results =
        for count <- sizes, cycle <- 1..2 do
          result = Load.load(__MODULE__, count, opts)
          saved_records = if persistent?, do: :ets.info(table, :size), else: 0

          storage_ets_bytes =
            if persistent?,
              do: :ets.info(table, :memory) * :erlang.system_info(:wordsize),
              else: 0

          storage_value_bytes =
            if persistent?,
              do:
                Enum.reduce(:ets.tab2list(table), 0, fn {_, bytes}, total ->
                  total + byte_size(bytes)
                end),
              else: 0

          if persistent? and saved_records != count, do: raise("unexpected saved record count")
          # Records survive activation stop by design. Remove them explicitly
          # before checking that processes, tasks, and tables return to baseline.
          if persistent?, do: :ets.delete_all_objects(table)
          :erlang.garbage_collect()
          after_stop = Load.snapshot()

          extra_processes =
            Process.list()
            |> Enum.reject(&MapSet.member?(baseline_pids, &1))
            |> Enum.filter(&Process.alive?/1)

          extra_tables = Enum.reject(:ets.all(), &MapSet.member?(baseline_tables, &1))

          if extra_processes != [] or extra_tables != [] do
            IO.inspect(%{processes: extra_processes, tables: extra_tables},
              label: "Retained resources"
            )

            raise("resources survived cleanup")
          end

          row =
            Map.merge(result, %{
              cycle: cycle,
              saved_records: saved_records,
              storage_ets_bytes: storage_ets_bytes,
              storage_value_bytes: storage_value_bytes,
              after_stop: after_stop
            })

          IO.puts(JSON.encode!(row))
          row
        end

      File.mkdir_p!("tmp/agent-server-activation")

      File.write!(
        "tmp/agent-server-activation/load#{if persistent?, do: "-persistent"}.json",
        JSON.encode!(%{
          elixir: System.version(),
          otp: List.to_string(:erlang.system_info(:otp_release)),
          schedulers: :erlang.system_info(:schedulers_online),
          source_sha256:
            :crypto.hash(:sha256, File.read!("lib/jido/agent_server.ex"))
            |> Base.encode16(case: :lower),
          baseline: baseline,
          results: results
        })
      )

      IO.puts(
        "PASS: repeated load, transient input release, recovery, and complete resource cleanup"
      )
    after
      Supervisor.stop(instance)
      if persistent? and :ets.whereis(table) != :undefined, do: :ets.delete(table)
    end
  end
end

AgentServerLoad.run()
