defmodule JidoPublicConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_public_consumer,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: false,
      deps: [{:jido, path: System.fetch_env!("JIDO_CANDIDATE_PATH")}]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
