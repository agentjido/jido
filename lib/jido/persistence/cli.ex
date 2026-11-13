defmodule Jido.Persistence.CLI do
  @moduledoc false

  alias Jido.Persistence.Config

  def parse!(argv, extra_switches) do
    switches =
      [
        adapter: :string,
        instance: :string,
        codec: :string,
        table: :string,
        path: :string
      ] ++ extra_switches

    case OptionParser.parse(argv, strict: switches) do
      {opts, [], []} ->
        duplicates = Keyword.keys(opts) -- Enum.uniq(Keyword.keys(opts))

        if duplicates == [],
          do: opts,
          else: Mix.raise("duplicate options: #{inspect(Enum.uniq(duplicates))}")

      {_opts, args, invalid} ->
        Mix.raise("invalid arguments: #{inspect(args ++ invalid)}")
    end
  end

  def config!(opts) do
    case {Keyword.get(opts, :instance), Keyword.get(opts, :adapter)} do
      {instance, nil} when is_binary(instance) -> instance_config!(instance, opts)
      {nil, adapter} when is_binary(adapter) -> adapter_config!(adapter, opts)
      {nil, nil} -> Mix.raise("pass --instance or --adapter")
      {_instance, _adapter} -> Mix.raise("pass only one of --instance or --adapter")
    end
  end

  def read_options(opts), do: [full: Keyword.get(opts, :full, false)]

  def export_options(opts) do
    [include_state: Keyword.get(opts, :include_state, false)]
  end

  def warn_sensitive!(opts) do
    cond do
      Keyword.get(opts, :full, false) ->
        Mix.shell().error("WARNING: output includes full persisted data")

      Keyword.get(opts, :include_state, false) ->
        Mix.shell().error("WARNING: output includes full persisted Agent state")

      true ->
        :ok
    end
  end

  def required!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> Mix.raise("missing required --#{key |> Atom.to_string() |> String.replace("_", "-")}")
    end
  end

  defp instance_config!(name, opts) do
    reject_options!(opts, [:codec, :table, :path], "--instance")
    instance = existing_module!(name)

    unless function_exported?(instance, :config, 0) and
             function_exported?(instance, :__jido_persistence__, 0) do
      Mix.raise("not a Jido instance module: #{name}")
    end

    runtime = instance.config()

    unless Keyword.keyword?(runtime) do
      Mix.raise("invalid Jido instance configuration: #{inspect(runtime)}")
    end

    declaration = Keyword.get(runtime, :persistence, instance.__jido_persistence__())

    case Config.open(declaration) do
      {:ok, %Config{} = config} -> config
      {:ok, nil} -> Mix.raise("Jido instance persistence is not configured: #{name}")
      {:error, reason} -> Mix.raise("invalid persistence profile: #{inspect(reason)}")
    end
  end

  defp adapter_config!(name, opts) do
    adapter = existing_module!(name)
    codec = codec!(Keyword.get(opts, :codec, "term"))
    store_opts = store_options!(adapter, opts)

    case Config.open(store: {adapter, store_opts}, codec: codec) do
      {:ok, config} -> config
      {:error, reason} -> Mix.raise("invalid persistence profile: #{inspect(reason)}")
    end
  end

  defp existing_module!(name) do
    module_name = if String.starts_with?(name, "Elixir."), do: name, else: "Elixir." <> name

    try do
      module = String.to_existing_atom(module_name)

      case Code.ensure_loaded(module) do
        {:module, ^module} -> module
        {:error, reason} -> Mix.raise("module cannot be loaded: #{name}: #{inspect(reason)}")
      end
    rescue
      ArgumentError -> Mix.raise("module is not loaded: #{name}")
    end
  end

  defp codec!("term"), do: Jido.Persistence.Codec.Term
  defp codec!("json"), do: Jido.Persistence.Codec.JSON
  defp codec!(value), do: Mix.raise("unsupported codec: #{value}")

  defp store_options!(Jido.Persistence.ETS, opts) do
    case Keyword.get(opts, :table) do
      nil -> []
      name -> [table: existing_atom!(name)]
    end
  end

  defp store_options!(Jido.Persistence.File, opts), do: [path: required!(opts, :path)]

  defp store_options!(adapter, _opts),
    do: Mix.raise("pass --instance for #{inspect(adapter)} so the tool can use its configured Store options")

  defp reject_options!(opts, keys, source) do
    case Enum.filter(keys, &Keyword.has_key?(opts, &1)) do
      [] -> :ok
      found -> Mix.raise("#{source} cannot be combined with #{inspect(found)}")
    end
  end

  defp existing_atom!(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> Mix.raise("atom is not loaded: #{name}")
  end
end
