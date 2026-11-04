defmodule Jido.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:ex_unit], ignore_warnings: ".dialyzer_ignore.exs"],
      package: package(),
      test_ignore_filters: test_ignore_filters(),
      test_coverage: test_coverage()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Jido.Application, []},
      extra_applications: [:crypto, :inets, :logger, :public_key, :ssl]
    ]
  end

  def cli do
    [
      preferred_envs: [
        bench: :prod,
        "bench.ai.fresh_workflow": :prod,
        "bench.ai.state_growth": :prod,
        ci: :test,
        coveralls: :test,
        "coveralls.json": :test,
        quality: :test,
        "quality.contract": :test,
        "quality.coverage": :test,
        "quality.report": :test,
        "test.authoring": :test,
        "test.all": :test,
        "test.bench": :test,
        "test.ci": :test,
        "test.contracts": :test,
        "test.examples": :test,
        "test.fuzz": :test,
        "test.live": :test,
        "test.load": :test,
        "test.peer": :test,
        "test.property": :test,
        "test.services": :test,
        "test.system": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "test/jido/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp test_coverage do
    [
      tool: ExCoveralls,
      output: "tmp/quality/coverage/coverdata",
      ignore_modules: [
        ~r/^Inspect\.Jido/,
        ~r/^JidoActionTest\./,
        ~r/^JidoSignalTest\./,
        ~r/^Jido\.Flow\.DSL\.Forms\.Flow\./,
        ~r/^Jido\.Flow\.DSL\.(?:Entity|Step|Output)$/,
        ~r/^Jido\.Flow\.DSL\.Forms\.(?:Map|Reduce|Choice(?:\.Option|\.Otherwise)?|Parallel(?:\.Action)?|Iterate(?:\.State)?|Invoke|Wait\.(?:Await|Timer|Selection(?:\.Await|\.Timer)?))$/,
        ~r/^Jido\.Action\.Generated\.Inline\./
      ],
      summary: [threshold: 90]
    ]
  end

  defp deps do
    [
      # Runtime
      {:multigraph, "~> 0.16.1-mg.5"},
      {:req_llm, "~> 1.29"},
      {:runic, "~> 0.1.0-alpha.13"},
      {:sched_ex, "~> 1.2.1"},
      {:spark, "~> 2.7.3"},
      {:splode, "~> 0.3.0"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.2"},
      {:yaml_elixir, "~> 2.12"},
      {:zoi, "~> 0.19.0", override: true},

      # Optional integrations
      {:bedrock, "~> 0.7.2", optional: true},
      {:bedrock_raft, "~> 0.10.0", optional: true},
      {:ecto_sql, "~> 3.14", optional: true},
      {:opentelemetry_api, "~> 1.0", optional: true},
      {:phoenix_pubsub, "~> 2.1", optional: true},

      # Development and test tools
      {:covenant, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18.5", only: [:dev, :test]},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false},

      # Test support
      {:ecto_sqlite3, "~> 0.24.1", only: :test},
      {:mimic, "~> 2.0", only: :test},
      {:opentelemetry, "~> 1.0", only: :test, runtime: false},
      {:plug, "~> 1.0", only: :test},
      {:postgrex, "~> 0.19 or ~> 1.0", only: :test},
      {:stream_data, "~> 1.4", only: :test, runtime: false}
    ]
  end

  defp aliases do
    [
      bench: "run test/bench/ai/react_memory.exs",
      "bench.ai.fresh_workflow": "run test/bench/ai/react_fresh_workflow.exs",
      "bench.ai.state_growth": "run test/bench/ai/react_state_growth.exs",
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test.ci",
        "credo --strict --min-priority higher",
        "credo --strict --mute-exit-status",
        "dialyzer --list-unused-filters",
        "ex_dna --max-clones 17",
        "reach.check --arch --smells"
      ],
      quality: [
        "quality.contract",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --min-priority higher",
        "credo --strict --mute-exit-status",
        "dialyzer --list-unused-filters",
        "ex_dna --max-clones 17",
        "reach.check --arch --smells"
      ],
      "test.authoring": test_alias("test/authoring", :authoring),
      "test.all": "test.ci",
      "test.bench": test_alias("test/bench", :bench),
      "test.ci": &run_test_ci/1,
      "test.contracts": "covenant.check",
      "test.examples": test_alias("test/examples", :example),
      "test.fuzz": fn args ->
        run_tagged_tests("test/property", :fuzz, args)
        check_property_reports!(args)
      end,
      "test.live": test_alias("test/live", :live),
      "test.load": test_alias("test/load", :load),
      "test.peer": test_alias("test", :peer),
      "test.property": test_alias("test/property", :property),
      "test.services": test_alias("test/system/services", :service),
      "test.system": test_alias("test/system", :system),
      "quality.contract": "test test/quality/quality_contract_test.exs --seed 0",
      "quality.coverage": fn args ->
        Mix.Task.run("app.start")
        Code.require_file("test/quality/support/contract.exs")
        Code.require_file("test/quality/support/component_proof.exs")
        Code.require_file("test/quality/support/coverage.exs")
        Jido.Quality.Coverage.run!(File.cwd!(), args)
      end,
      "quality.report": fn args ->
        Mix.Task.run("app.start")
        Code.require_file("test/quality/support/contract.exs")
        Code.require_file("test/quality/support/component_proof.exs")
        Code.require_file("test/quality/support/report.exs")
        Jido.Quality.Report.run!(File.cwd!(), args)
      end
    ]
  end

  defp test_alias(default_path, tag) do
    fn args -> run_tagged_tests(default_path, tag, args) end
  end

  defp run_tagged_tests(default_path, tag, args) do
    explicit_path? = Enum.any?(args, &test_path?/1)
    default_path? = File.exists?(default_path)

    if default_path? or explicit_path? do
      paths = if default_path? and not explicit_path?, do: [default_path], else: []
      Mix.Task.run("test", ["--only", Atom.to_string(tag), "--seed", "0"] ++ paths ++ args)
    else
      Mix.shell().info("No #{tag} tests found under #{default_path}")
    end
  end

  defp run_test_ci([]) do
    [
      ["quality.contract"],
      ["test", "--seed", "0"],
      ["test.authoring"],
      ["test.contracts"],
      ["test.examples"],
      ["test.property"],
      ["test.fuzz"],
      ["test.system"],
      ["test.load"],
      ["test.peer"],
      ["test.bench"]
    ]
    |> Enum.each(&run_mix_task!/1)
  end

  defp run_test_ci(args), do: Mix.raise("mix test.ci does not accept arguments: #{inspect(args)}")

  defp run_mix_task!(args) do
    mix = System.find_executable("mix") || Mix.raise("mix executable is not available")
    Mix.shell().info("test.ci: mix #{Enum.join(args, " ")}")

    case System.cmd(mix, args, env: [{"MIX_ENV", "test"}], stderr_to_stdout: true) do
      {output, 0} -> IO.write(output)
      {output, status} -> Mix.raise("mix #{Enum.join(args, " ")} failed with status #{status}\n#{output}")
    end
  end

  defp test_path?(argument) do
    not String.starts_with?(argument, "-") and File.exists?(argument)
  end

  defp check_property_reports!(args) do
    paths = Enum.filter(args, &test_path?/1)
    all? = paths == [] or Enum.any?(paths, &(Path.expand(&1) == Path.expand("test/property")))

    if all? or Enum.any?(paths, &String.contains?(Path.expand(&1), "/test/property/signal")) do
      Code.require_file("test/property/signal/support/report.exs")
      JidoTest.Property.Signal.Report.check!()
    end

    if all? or Enum.any?(paths, &String.contains?(Path.expand(&1), "/test/property/action_flow")) do
      Code.require_file("test/property/action_flow/support/report.exs")
      JidoTest.Property.ActionFlow.Report.check!()
    end
  end

  defp test_ignore_filters do
    [
      ~r/^test\/fixtures\//,
      ~r/^test\/contracts\//,
      ~r/^test\/authoring\/support\//,
      ~r/^test\/examples\/support\//,
      ~r{^test/bench/(?:action_flow/(?:dsl_compile|fixtures|flow_compile|flow_run|react_stress|support)|ai/(?:react_fresh_workflow|react_memory|react_state_growth|react_support)|signal/run)\.exs$},
      ~r{^test/bench/(?:signal/support|support)/},
      ~r/^test\/quality\/support\//,
      ~r|^test/property/[^/]+/support/|,
      ~r|^test/system/services/support/|,
      ~r|^test/system/runtime/core/support/|,
      ~r/^test\/jido\/core_contract\/.*(?:support|configuration_support)\.ex$/
    ]
  end

  defp package do
    [files: [".formatter.exs", "lib", "mix.exs"]]
  end
end
