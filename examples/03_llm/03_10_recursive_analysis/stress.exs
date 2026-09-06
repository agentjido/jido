# Run from the project root with mix run. All data and model calls are local.
alias Jido.AgentServer, as: Server
alias Jido.Examples.RecursiveLanguageModel, as: RLM
alias Jido.Examples.RecursiveLanguageModel.{Corpus, Fixtures, ScriptedModel}

{opts, rest, invalid} =
  OptionParser.parse(System.argv(),
    strict: [records: :integer, leaf: :integer, agents: :integer, rounds: :integer]
  )

if rest != [] or invalid != [],
  do: raise(ArgumentError, "use --records, --leaf, --agents, and --rounds")

config = Map.merge(%{records: 100_000, leaf: 64, agents: 4, rounds: 1}, Map.new(opts))

unless Enum.all?(config, fn {_key, value} -> value > 0 end) and config.agents <= 64 do
  raise ArgumentError, "all values must be positive; agents must be at most 64"
end

rows = Fixtures.logs(config.records)
expected = rows |> Enum.filter(&(&1.status == :failed)) |> Enum.frequencies_by(& &1.service)
{:ok, corpus} = Corpus.start_link(%{"stress-v1" => rows})
{:ok, info} = Corpus.describe(corpus, "stress-v1")
{:ok, jido} = Jido.start_link(name: RLM.StressInstance)

# A full binary tree cannot use more than 2 * records - 1 recursive calls.
limits = %{
  max_depth: 64,
  max_calls: 2 * config.records - 1,
  max_steps: 2 * (2 * config.records - 1),
  max_bytes: info.bytes,
  max_read_records: config.leaf
}

try do
  {elapsed_us, results} =
    :timer.tc(fn ->
      1..config.agents
      |> Task.async_stream(
        fn index ->
          {:ok, model} = ScriptedModel.start_link(chunk_size: config.leaf)
          {:ok, agent} = Jido.start_agent(RLM.StressInstance, RLM, exec_opts: [timeout: 120_000])

          try do
            runs =
              for round <- 1..config.rounds do
                {run_us, result} =
                  :timer.tc(fn ->
                    RLM.analyze(agent, "stress-v1", {ScriptedModel, model}, {Corpus, corpus},
                      limits: limits,
                      timeout: 125_000
                    )
                  end)

                case result do
                  {:ok, committed} ->
                    unless committed.state.counts == expected and
                             committed.state.usage.records_read == config.records and
                             committed.state.usage.bytes_read == info.bytes and
                             committed.state.usage.peak_read_records <= config.leaf and
                             Server.snapshot(agent).state_version == round do
                      raise "stress result failed validation"
                    end

                    %{
                      round: round,
                      elapsed_ms: Float.round(run_us / 1_000, 1),
                      usage: committed.state.usage
                    }

                  {:error, error} ->
                    raise "stress run failed: #{inspect(error)}"
                end
              end

            %{agent: index, commits: config.rounds, runs: runs}
          after
            Server.stop(agent)
            GenServer.stop(model)
          end
        end,
        max_concurrency: config.agents,
        timeout: config.rounds * 130_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> raise "stress task failed: #{inspect(reason)}"
      end)
    end)

  IO.puts(
    Jason.encode!(
      %{
        config: config,
        runtime: %{
          elixir: System.version(),
          otp: List.to_string(:erlang.system_info(:otp_release))
        },
        elapsed_ms: Float.round(elapsed_us / 1_000, 1),
        corpus_bytes: info.bytes,
        expected_counts: expected,
        successful_runs: config.agents * config.rounds,
        results: results
      },
      pretty: true
    )
  )
after
  Supervisor.stop(jido)
  GenServer.stop(corpus)
end
