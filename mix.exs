defmodule Jido.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :jido,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "Jido",
      description: "An Elixir SDK for building AI Agents and Workflows.",
      source_url: "https://github.com/mikehostetler/jido",
      homepage_url: "https://github.com/mikehostetler/jido",
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "Jido",
      source_ref: "v#{@version}",
      source_url: "https://github.com/mikehostetler/jido",
      extras: ["guides/getting-started.md", "guides/workflows.md"]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/mikehostetler/jido"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:deep_merge, "~> 1.0"},
      {:elixir_uuid, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:ok, "~> 2.3"},
      {:phoenix_pubsub, "~> 2.1"},
      {:proper_case, "~> 1.3"},
      {:telemetry, "~> 1.3"},
      {:typed_struct, "~> 0.3.0"},

      # Testing
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.7", only: [:dev, :test]},
      {:mock, "~> 0.3.8", only: [:dev, :test]},
      {:private, "~> 0.1.2", only: [:dev, :test]},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      test: "test --trace",

      # Run to check the quality of your code
      q: ["quality"],
      quality: [
        "format",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "dialyzer --format dialyxir",
        "sobelow --config",
        "credo --all"
      ]
    ]
  end
end
