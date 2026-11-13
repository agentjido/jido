defmodule Mix.Tasks.Jido.Persistence.Inspect do
  use Mix.Task

  @shortdoc "Inspects one Jido persistence record"
  @requirements ["app.config"]

  @impl true
  def run(argv) do
    opts =
      Jido.Persistence.CLI.parse!(argv,
        key: :string,
        namespace: :string,
        id: :string,
        partition: :string,
        full: :boolean
      )

    config = Jido.Persistence.CLI.config!(opts)
    key = record_key!(opts)
    Jido.Persistence.CLI.warn_sensitive!(opts)

    case Jido.Persistence.Inspector.read(config, key, Jido.Persistence.CLI.read_options(opts)) do
      {:ok, value} ->
        {:ok, line} = Jido.Persistence.Inspector.json_line(key, value)
        Mix.shell().info(String.trim_trailing(line))

      {:error, reason} ->
        Mix.raise("inspection failed: #{inspect(reason)}")
    end
  end

  defp record_key!(opts) do
    case {Keyword.get(opts, :key), Keyword.get(opts, :namespace), Keyword.get(opts, :id)} do
      {key, nil, nil} when is_binary(key) ->
        key

      {nil, namespace, id} when is_binary(namespace) and is_binary(id) ->
        agent_key!(namespace, id, Keyword.get(opts, :partition))

      _other ->
        Mix.raise("pass --key, or pass --namespace and --id with optional --partition")
    end
  end

  defp agent_key!(namespace, id, partition) do
    address = Jido.Agent.Address.new!(namespace: namespace, id: id, partition: partition)
    Jido.Persistence.agent_key(address)
  rescue
    error -> Mix.raise("invalid Agent Address: #{Exception.message(error)}")
  end
end
