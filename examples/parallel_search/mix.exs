defmodule ParallelSearch.MixProject do
  use Mix.Project

  def project do
    [
      app: :parallel_search_example,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [
        {:jido, path: "../.."},
        {:ex_mcp, "~> 1.6.0"},
        {:jason, "~> 1.4"},
        {:bypass, "~> 2.1", only: :test}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
