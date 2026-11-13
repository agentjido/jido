defmodule Mix.Tasks.Jido.Persistence.Export do
  use Mix.Task

  @shortdoc "Exports Jido persistence records as JSONL"
  @requirements ["app.config"]

  @impl true
  def run(argv) do
    opts =
      Jido.Persistence.CLI.parse!(argv,
        prefix: :string,
        output: :string,
        limit: :integer,
        force: :boolean,
        include_state: :boolean
      )

    config = Jido.Persistence.CLI.config!(opts)
    prefix = Keyword.get(opts, :prefix, "jido:")
    output = Keyword.get(opts, :output, "-")
    export_opts = [limit: Keyword.get(opts, :limit, 100)] ++ Jido.Persistence.CLI.export_options(opts)
    Jido.Persistence.CLI.warn_sensitive!(opts)

    result =
      if output == "-" do
        Jido.Persistence.Inspector.export_jsonl(config, prefix, :stdio, export_opts)
      else
        export_file(config, prefix, output, export_opts, Keyword.get(opts, :force, false))
      end

    case result do
      {:ok, _count} when output == "-" -> :ok
      {:ok, count} -> Mix.shell().info("exported #{count} records")
      {:error, reason} -> Mix.raise("export failed: #{inspect(reason)}")
    end
  end

  defp export_file(config, prefix, output, export_opts, force?) do
    modes = if force?, do: [:write, :binary], else: [:write, :exclusive, :binary]

    case File.open(output, modes) do
      {:ok, io} ->
        try do
          Jido.Persistence.Inspector.export_jsonl(config, prefix, io, export_opts)
        after
          File.close(io)
        end

      {:error, :eexist} ->
        Mix.raise("output exists; pass --force to replace it: #{output}")

      {:error, reason} ->
        Mix.raise("cannot open output: #{inspect(reason)}")
    end
  end
end
