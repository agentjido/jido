defmodule InlineConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :inline_consumer,
      version: "0.1.0",
      # Rapid rebuilds can share a directory timestamp. Compare module names.
      reliable_dir_mtime: false,
      deps: [],
      releases: [inline_consumer: [include_erts: false]]
    ]
  end

  def application, do: [extra_applications: [:jido]]
end
