# Run from the jido repository with `elixir test/system/burn_in.exs`.
# Each child is a fresh Mix/BEAM run. The selected tests retain their own
# state, cleanup and observability assertions; this is not a second framework.
{opts, [], []} =
  OptionParser.parse(System.argv(), strict: [runs: :integer, rounds: :integer, seed: :integer])

runs = Keyword.get(opts, :runs, 5)
rounds = Keyword.get(opts, :rounds, 100)
seed = Keyword.get(opts, :seed, 93)

unless runs in 1..100 and rounds in 1..1_000 and seed >= 0,
  do: raise("runs must be 1..100, rounds 1..1000, seed non-negative")

unless File.regular?("mix.exs") and File.dir?("test/system/runtime"),
  do: raise("Run from the jido package")

for offset <- 0..(runs - 1) do
  current_seed = seed + offset
  IO.puts("System burn-in #{offset + 1}/#{runs}; seed=#{current_seed}; rounds=#{rounds}")

  {_stream, status} =
    System.cmd(
      "mix",
      [
        "test",
        "test/system/runtime/turn_model_test.exs",
        "test/system/runtime/peers_test.exs",
        "--only",
        "scenario:burn_in",
        "--seed",
        to_string(current_seed)
      ],
      env: [
        {"MIX_ENV", "test"},
        {"JIDO_SYSTEM_MODEL_SEED", to_string(current_seed)},
        {"JIDO_SYSTEM_MODEL_ROUNDS", to_string(rounds)}
      ],
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    )

  if status != 0, do: System.halt(status)
end
