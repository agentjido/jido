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
      dialyzer: [plt_add_apps: [:ex_unit]],
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
        ci: :test,
        quality: :test,
        "test.authoring": :test,
        "test.bench": :test,
        "test.ci": :test,
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
      bench: "run bench/react_memory.exs",
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test.ci",
        "credo --strict",
        "dialyzer",
        "ex_dna",
        "reach.check --arch --smells"
      ],
      quality: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "ex_dna",
        "reach.check --arch --smells"
      ],
      "test.authoring": test_alias("test/authoring", :authoring),
      "test.bench": test_alias("test/bench", :bench),
      "test.ci": [
        "test",
        "test.examples",
        "test.property",
        "test.fuzz",
        "test.system",
        "test.load",
        "test.peer",
        "test.bench"
      ],
      "test.examples": test_alias("test/examples", :example),
      "test.fuzz": test_alias("test/property", :fuzz),
      "test.live": test_alias("test/live", :live),
      "test.load": test_alias("test/load", :load),
      "test.peer": test_alias("test", :peer),
      "test.property": test_alias("test/property", :property),
      "test.services": test_alias("test/system/services", :service),
      "test.system": test_alias("test/system", :system)
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

  defp test_path?(argument) do
    not String.starts_with?(argument, "-") and File.exists?(argument)
  end

  defp test_ignore_filters do
    [
      ~r/^test\/fixtures\//,
      ~r/^test\/contracts\//,
      ~r/^test\/jido\/core_authoring\/support\//,
      ~r/^test\/jido\/core_contract\/.*(?:support|configuration_support)\.ex$/
    ]
  end

  defp package do
    [files: [".formatter.exs", "lib", "mix.exs"]]
  end
end
