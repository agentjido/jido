defmodule Jido.Discovery do
  @moduledoc """
  Builds the runtime Registry used by JSON codecs and code discovery.

  Discovery scans configured application module lists and explicit modules.
  Modules publish static entries through `__jido_catalog_manifest__/0`. Document
  codecs implement the `Jido.Codec.Contract` behaviour. Reads use an immutable
  Registry in `:persistent_term`.

      config :jido, Jido.Discovery,
        applications: [:my_app, :jido],
        modules: [MyApp.SpecialAction]

  Use an application allowlist when stored definitions are accepted from
  users. Discovery is an inventory service. It does not grant permission to
  execute a discovered module.

  Use `list/0`, `list/1`, `get/2`, and `get_by_target/2` for all entry kinds.

  Inline Actions remain implementation details of their owner modules.

  `jido` starts one asynchronous scan of all loaded applications. This
  happens once when the consolidated package starts.
  Applications loaded after this scan can call `refresh/1`.
  """

  require Logger

  alias Jido.Codec.{Contract, Manifest, Registry}

  @registry_key {__MODULE__, :registry}
  @default_applications :loaded
  @option_keys [:applications, :modules]

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {Task, :start_link, [fn -> initialize_child(opts) end]},
      restart: :temporary,
      type: :worker
    }
  end

  @doc "Returns true when the first Registry build is complete."
  @spec ready?() :: boolean()
  def ready?, do: match?(%Registry{}, :persistent_term.get(@registry_key, :not_initialized))

  @doc "Returns the current immutable runtime Codec Registry."
  @spec registry() :: Registry.t()
  def registry do
    case :persistent_term.get(@registry_key, :not_initialized) do
      :not_initialized ->
        raise Jido.Codec.Error.internal(
                :registry_not_initialized,
                "Codec Registry is not initialized"
              )

      {:error, reason} ->
        raise Jido.Codec.Error.internal(
                :registry_initialization_failed,
                "Codec Registry initialization failed: #{inspect(reason)}",
                %{reason: reason}
              )

      %Registry{} = registry ->
        registry
    end
  end

  @doc "Lists all discovered entries, or entries of one kind."
  @spec list() :: [Registry.manifest()]
  def list, do: Registry.list(registry())

  @doc "Lists discovered entries of one kind."
  @spec list(Registry.kind()) :: [Registry.manifest()]
  def list(kind), do: Registry.list(registry(), kind)

  @doc "Returns a discovered entry for a stable identifier and `vsn`."
  @spec get(String.t(), pos_integer()) :: Registry.manifest() | nil
  def get(id, vsn), do: Registry.get(registry(), id, vsn)

  @doc "Returns a discovered entry for an exact kind and target."
  @spec get_by_target(Registry.kind(), term()) :: Registry.manifest() | nil
  def get_by_target(kind, target), do: Registry.get_by_target(registry(), kind, target)

  @doc "Rebuilds and atomically replaces the complete Codec Registry."
  @spec refresh(keyword()) :: :ok | {:error, term()}
  def refresh(opts \\ []) do
    with {:ok, modules} <- discovery_modules(opts),
         {:ok, registry} <- build_registry(modules) do
      :persistent_term.put(@registry_key, registry)
      :ok
    end
  end

  @doc false
  @spec initialize(keyword()) :: :ok | {:error, term()}
  def initialize(opts \\ []), do: refresh(opts)

  defp initialize_child(opts) do
    case initialize(opts) do
      :ok ->
        :ok

      {:error, reason} ->
        unless match?(%Registry{}, :persistent_term.get(@registry_key, :not_initialized)),
          do: :persistent_term.put(@registry_key, {:error, reason})

        Logger.warning("Jido Discovery did not refresh: #{inspect(reason)}")
    end
  end

  defp discovery_modules(opts) do
    with {:ok, opts} <- validate_options(opts, :invalid_discovery_options),
         {:ok, config} <- discovery_config(),
         {:ok, applications} <- application_option(opts, config),
         {:ok, configured_modules} <- module_option(config),
         {:ok, option_modules} <- module_option(opts),
         {:ok, application_modules} <- modules_for_applications(applications) do
      modules =
        application_modules
        |> Kernel.++(configured_modules)
        |> Kernel.++(option_modules)
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, modules}
    end
  end

  defp discovery_config do
    case Application.get_env(:jido, __MODULE__, []) do
      config when is_list(config) ->
        case validate_options(config, :invalid_discovery_config) do
          {:ok, config} ->
            {:ok, config}

          {:error, {:invalid_discovery_config, keys}} ->
            {:error, {:invalid_discovery_config, {:unknown_options, keys}}}
        end

      config ->
        {:error, {:invalid_discovery_config, config}}
    end
  end

  defp validate_options(options, error) when is_list(options) do
    if Keyword.keyword?(options) do
      case Keyword.validate(options, @option_keys) do
        {:ok, options} -> {:ok, options}
        {:error, keys} -> {:error, {error, keys}}
      end
    else
      {:error, {error, options}}
    end
  end

  defp validate_options(options, error), do: {:error, {error, options}}

  defp application_option(opts, config) do
    value =
      Keyword.get(opts, :applications, Keyword.get(config, :applications, @default_applications))

    case value do
      :loaded -> {:ok, loaded_applications()}
      applications when is_list(applications) -> validate_atoms(:applications, applications)
      other -> {:error, {:invalid_applications, other}}
    end
  end

  defp module_option(options) do
    case Keyword.get(options, :modules, []) do
      modules when is_list(modules) -> validate_atoms(:modules, modules)
      other -> {:error, {:invalid_modules, other}}
    end
  end

  defp validate_atoms(_name, []), do: {:ok, []}

  defp validate_atoms(name, values) do
    if Enum.all?(values, &(is_atom(&1) and &1 not in [nil, true, false])) do
      {:ok, values}
    else
      {:error, {invalid_atom_list(name), values}}
    end
  end

  defp invalid_atom_list(:applications), do: :invalid_applications
  defp invalid_atom_list(:modules), do: :invalid_modules

  defp loaded_applications do
    Application.loaded_applications()
    |> Enum.map(&elem(&1, 0))
  end

  defp modules_for_applications(applications) do
    Enum.reduce_while(applications, {:ok, []}, fn application, {:ok, result} ->
      case Application.spec(application, :modules) do
        modules when is_list(modules) ->
          available = Enum.reject(modules, &(:code.which(&1) == :non_existing))
          {:cont, {:ok, available ++ result}}

        nil ->
          {:halt, {:error, {:application_not_loaded, application}}}
      end
    end)
  end

  defp build_registry(modules) do
    with {:ok, {entries, codecs}} <-
           Enum.reduce_while(modules, {:ok, {[], []}}, fn module, {:ok, {entries, codecs}} ->
             case discover(module) do
               {:ok, found_entries, found_codecs} ->
                 {:cont, {:ok, {found_entries ++ entries, found_codecs ++ codecs}}}

               {:error, error} ->
                 {:halt, {:error, error}}
             end
           end) do
      Registry.new_discovered(entries, codecs)
    end
  end

  defp discover(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> discover_loaded(module)
      {:error, reason} -> {:error, {:module_not_loaded, reason}}
    end
  end

  defp discover_loaded(module) do
    if function_exported?(module, :__jido_inline_action__, 0) do
      {:ok, [], []}
    else
      with {:ok, entries} <- discover_entries(module),
           {:ok, codecs} <- codec_metadata(module),
           do: {:ok, entries, codecs}
    end
  end

  defp discover_entries(module) do
    if function_exported?(module, :__jido_catalog_manifest__, 0) do
      with {:ok, entries} <- Manifest.validate(module, module.__jido_catalog_manifest__()) do
        {:ok, Enum.map(entries, &decorate_entry/1)}
      end
    else
      {:ok, []}
    end
  rescue
    error -> {:error, {:codec_manifest_failed, module, error}}
  catch
    kind, reason -> {:error, {:codec_manifest_failed, module, {kind, reason}}}
  end

  defp codec_metadata(module) do
    if codec_module?(module) do
      case Contract.metadata(module) do
        {:ok, metadata} ->
          {:ok, [Map.put(metadata, :module, module)]}

        {:error, {:metadata_failure, kind, reason}} ->
          {:error, {:codec_failed, module, {kind, reason}}}

        {:error, {:invalid_metadata, metadata}} ->
          {:error, {:invalid_codec, module, metadata}}

        {:error, :invalid_contract} ->
          {:error, {:invalid_codec, module, :invalid_contract}}
      end
    else
      {:ok, []}
    end
  end

  defp codec_module?(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.member?(Jido.Codec.Contract)
  end

  defp decorate_entry(entry) do
    Map.put(entry, :application, Application.get_application(entry.provider))
  end
end
