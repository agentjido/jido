defmodule Jido.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
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
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1", optional: true},
      {:spark, "~> 2.7.3"},
      {:splode, "~> 0.3.0"},
      {:telemetry, "~> 1.3"},
      {:zoi, "~> 0.18.11"}
    ]
  end
end
