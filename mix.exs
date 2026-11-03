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
      {:bedrock, "~> 0.7.2", optional: true},
      {:bedrock_raft, "~> 0.10.0", optional: true},
      {:ecto_sql, "~> 3.14", optional: true},
      {:multigraph, "~> 0.16.1-mg.5"},
      {:opentelemetry_api, "~> 1.0", optional: true},
      {:phoenix_pubsub, "~> 2.1", optional: true},
      {:req_llm, "~> 1.29"},
      {:runic,
       git: "https://github.com/zblanco/runic.git", ref: "0c15a9c107137b8c13ebbc3340abd207d8f1f3ff", override: true},
      {:spark, "~> 2.7.3"},
      {:splode, "~> 0.3.0"},
      {:sched_ex, "~> 1.2.1"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.2"},
      {:yaml_elixir, "~> 2.12"},
      {:zoi, "~> 0.19.0", override: true},
      {:covenant, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:ecto_sqlite3, "~> 0.24.1", only: :test},
      {:mimic, "~> 2.0", only: :test},
      {:opentelemetry, "~> 1.0", only: :test, runtime: false},
      {:plug, "~> 1.0", only: :test},
      {:postgrex, "~> 0.19 or ~> 1.0", only: :test},
      {:stream_data, "~> 1.4", only: :test, runtime: false}
    ]
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
