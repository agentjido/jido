defmodule Jido.Catalog.Discovery do
  @moduledoc """
  Builds and atomically publishes the application-wide Catalog.

  Discovery scans configured application module lists and explicit modules.
  Modules publish static entries through `__jido_catalog_manifest__/0`. Document
  codecs implement the `Jido.Codec.Contract` behaviour. One atomic published
  value contains the immutable Catalog and the private Codec Index.

      config :jido, Jido.Catalog.Discovery,
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

  alias Jido.Catalog
  alias Jido.Catalog.{Entry, Manifest}
  alias Jido.Codec.{Contract, Index}

  @snapshot_key {:jido, :catalog_snapshot}
  @default_applications :loaded
  @option_keys [:applications, :modules]
  @included_plugins [
    Jido.AI.Agent.Plugin,
    Jido.Plugin.Scheduler,
    Jido.Plugin.SensorManager,
    Jido.Plugin.Bus.Manager,
    Jido.Plugin.Bus.Client,
    Jido.Plugin.Heartbeat,
    Jido.Plugin.Audit
  ]
  @base_entry %{
    id: "jido/schemas/map",
    kind: :schema,
    vsn: 1,
    target: Jido.Joi.map(),
    provider: Jido.Codec,
    application: :jido,
    name: "Map schema",
    description: "The default Jido map schema"
  }

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

  @doc "Returns true when the first Catalog build is complete."
  @spec ready?() :: boolean()
  def ready?, do: match?(%{catalog: %Catalog{}, codecs: %Index{}}, published())

  @doc "Lists the first-party Plugin modules included in this Jido release."
  @spec included_plugins() :: [module()]
  def included_plugins, do: @included_plugins

  @doc "Returns the current immutable application-wide Catalog."
  @spec catalog() :: Catalog.t()
  def catalog do
    case published() do
      :not_initialized -> raise_not_initialized()
      {:error, reason} -> raise_initialization_failed(reason)
      %{catalog: %Catalog{} = catalog} -> catalog
    end
  end

  @doc false
  @spec codec_index() :: Index.t()
  def codec_index do
    case published() do
      :not_initialized -> raise_not_initialized()
      {:error, reason} -> raise_initialization_failed(reason)
      %{codecs: %Index{} = codecs} -> codecs
    end
  end

  @doc "Lists all discovered entries, or entries of one kind."
  @spec list() :: [Entry.t()]
  def list, do: Catalog.list(catalog())

  @doc "Lists discovered entries of one kind."
  @spec list(Entry.kind()) :: [Entry.t()]
  def list(kind), do: Catalog.list(catalog(), kind)

  @doc "Returns a discovered entry for a stable identifier and `vsn`."
  @spec get(String.t(), pos_integer()) :: Entry.t() | nil
  def get(id, vsn), do: Catalog.get(catalog(), id, vsn)

  @doc "Returns a discovered entry for an exact kind and target."
  @spec get_by_target(Entry.kind(), term()) :: Entry.t() | nil
  def get_by_target(kind, target), do: Catalog.get_by_target(catalog(), kind, target)

  @doc "Rebuilds and atomically replaces the complete Catalog and Codec index."
  @spec refresh(keyword()) :: :ok | {:error, term()}
  def refresh(opts \\ []) do
    with {:ok, sources} <- discovery_modules(opts),
         {:ok, entries, codecs} <- discover_all(sources),
         {:ok, base_entry} <- Entry.new(@base_entry),
         entries = [base_entry | entries],
         {:ok, catalog} <- Catalog.new(entries),
         {:ok, index} <- Index.new(codecs) do
      :persistent_term.put(@snapshot_key, %{catalog: catalog, codecs: index})
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
        unless match?(%{catalog: %Catalog{}, codecs: %Index{}}, published()),
          do: :persistent_term.put(@snapshot_key, {:error, reason})

        Logger.warning("Jido Catalog Discovery did not refresh: #{inspect(reason)}")
    end
  end

  defp discovery_modules(opts) do
    with {:ok, opts} <- validate_options(opts, :invalid_discovery_options),
         {:ok, config} <- discovery_config(),
         {:ok, applications} <- application_option(opts, config),
         {:ok, configured_modules} <- module_option(config),
         {:ok, option_modules} <- module_option(opts),
         {:ok, application_modules} <- modules_for_applications(applications),
         {:ok, configured_sources} <- modules_with_applications(configured_modules),
         {:ok, option_sources} <- modules_with_applications(option_modules) do
      sources =
        application_modules
        |> Kernel.++(configured_sources)
        |> Kernel.++(option_sources)
        |> Enum.uniq()
        |> Enum.sort_by(fn {module, application} ->
          {Atom.to_string(application), Atom.to_string(module)}
        end)

      {:ok, sources}
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
      modules when is_list(modules) -> validate_modules(modules)
      other -> {:error, {:invalid_modules, other}}
    end
  end

  defp validate_modules(modules) do
    if Enum.all?(modules, &valid_module_source?/1),
      do: {:ok, modules},
      else: {:error, {:invalid_modules, modules}}
  end

  defp valid_module_source?({module, application}),
    do: valid_atom?(module) and valid_atom?(application)

  defp valid_module_source?(module), do: valid_atom?(module)

  defp validate_atoms(_name, []), do: {:ok, []}

  defp validate_atoms(name, values) do
    if Enum.all?(values, &valid_atom?/1) do
      {:ok, values}
    else
      {:error, {invalid_atom_list(name), values}}
    end
  end

  defp invalid_atom_list(:applications), do: :invalid_applications
  defp invalid_atom_list(:modules), do: :invalid_modules
  defp valid_atom?(value), do: is_atom(value) and value not in [nil, true, false]

  defp loaded_applications do
    Application.loaded_applications()
    |> Enum.map(&elem(&1, 0))
  end

  defp modules_for_applications(applications) do
    Enum.reduce_while(applications, {:ok, []}, fn application, {:ok, result} ->
      case Application.spec(application, :modules) do
        modules when is_list(modules) ->
          available =
            modules
            |> Enum.reject(&(:code.which(&1) == :non_existing))
            |> Enum.map(&{&1, application})

          {:cont, {:ok, available ++ result}}

        nil ->
          {:halt, {:error, {:application_not_loaded, application}}}
      end
    end)
  end

  defp modules_with_applications(modules) do
    Enum.reduce_while(modules, {:ok, []}, fn module, {:ok, sources} ->
      case module do
        {module, application} ->
          {:cont, {:ok, [{module, application} | sources]}}

        module ->
          with {:module, ^module} <- Code.ensure_loaded(module),
               application when application not in [nil, true, false] <-
                 Application.get_application(module) do
            {:cont, {:ok, [{module, application} | sources]}}
          else
            {:error, reason} -> {:halt, {:error, {:module_not_loaded, reason}}}
            nil -> {:halt, {:error, {:module_application_not_found, module}}}
          end
      end
    end)
  end

  defp discover_all(sources) do
    Enum.reduce_while(sources, {:ok, [], []}, fn source, {:ok, entries, codecs} ->
      case discover(source) do
        {:ok, found_entries, found_codecs} ->
          {:cont, {:ok, found_entries ++ entries, found_codecs ++ codecs}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp discover({module, application}) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> discover_loaded(module, application)
      {:error, reason} -> {:error, {:module_not_loaded, reason}}
    end
  end

  defp discover_loaded(module, application) do
    if function_exported?(module, :__jido_inline_action__, 0) do
      {:ok, [], []}
    else
      with {:ok, entries} <- discover_entries(module, application),
           {:ok, codecs} <- codec_metadata(module),
           do: {:ok, entries, codecs}
    end
  end

  defp discover_entries(module, application) do
    if function_exported?(module, :__jido_catalog_manifest__, 0) do
      with {:ok, %Manifest{entries: entries}} <-
             Manifest.new(module, application, module.__jido_catalog_manifest__()) do
        {:ok, entries}
      end
    else
      {:ok, []}
    end
  rescue
    error -> {:error, {:catalog_manifest_failed, module, error}}
  catch
    kind, reason -> {:error, {:catalog_manifest_failed, module, {kind, reason}}}
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

  defp published, do: :persistent_term.get(@snapshot_key, :not_initialized)

  defp raise_not_initialized do
    raise Jido.Codec.Error.internal(
            :catalog_not_initialized,
            "Catalog is not initialized"
          )
  end

  defp raise_initialization_failed(reason) do
    raise Jido.Codec.Error.internal(
            :catalog_initialization_failed,
            "Catalog initialization failed: #{inspect(reason)}",
            %{reason: reason}
          )
  end
end
