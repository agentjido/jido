defmodule Jido.Discovery do
  @moduledoc """
  Builds the runtime Registry used by JSON authoring and code discovery.

  Discovery scans configured application module lists and explicit modules.
  Modules publish static entries through `__jido_authoring__/0`. Document
  codecs publish metadata through `__jido_authoring_codec__/0`. Reads use an
  immutable Registry in `:persistent_term`.

      config :jido, Jido.Discovery,
        applications: [:my_app, :jido],
        modules: [MyApp.SpecialAction]

  Use an application allowlist when stored definitions are accepted from
  users. Discovery is an inventory service. It does not grant permission to
  execute a discovered module.

  Use `list/0`, `list/1`, `get/2`, and `get_by_target/2` for all entry kinds.

  Inline Actions remain implementation details of their owner modules.

  `jido` starts one asynchronous scan of all loaded applications. The
  Discovery process starts immediately and completes the scan after application
  startup continues. A caller that needs the Registry waits for the scan.
  Applications loaded after this scan can call `refresh/1`.
  """

  use GenServer

  require Logger

  alias Jido.Authoring.{Codec, Manifest, Registry}

  @registry_key {__MODULE__, :registry}
  @default_applications :loaded
  @default_provider_timeout_ms 30_000
  @option_keys [:applications, :modules, :provider_timeout_ms]
  @server_option_keys [:name, :registry_key]

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {server_opts, discovery_opts} = Keyword.split(opts, @server_option_keys)
    name = Keyword.get(server_opts, :name, __MODULE__)
    registry_key = Keyword.get(server_opts, :registry_key, @registry_key)
    genserver_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, {discovery_opts, registry_key}, genserver_opts)
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }
  end

  @doc "Returns true when the first Registry build is complete."
  @spec ready?() :: boolean()
  def ready?, do: match?(%Registry{}, :persistent_term.get(@registry_key, :not_initialized))

  @doc "Waits for and returns the current immutable runtime authoring Registry."
  @spec registry() :: Registry.t()
  def registry do
    case :persistent_term.get(@registry_key, :not_initialized) do
      :loading ->
        __MODULE__ |> GenServer.call(:registry, :infinity) |> unwrap_registry()

      :not_initialized ->
        raise_registry_not_initialized()

      {:error, reason} ->
        raise_registry_initialization_failed(reason)

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

  @doc "Rebuilds and atomically replaces the complete authoring Registry."
  @spec refresh(keyword()) :: :ok | {:error, term()}
  def refresh(opts \\ []), do: GenServer.call(__MODULE__, {:refresh, opts}, :infinity)

  @doc false
  @spec initialize(keyword()) :: :ok | {:error, term()}
  def initialize(opts \\ []), do: refresh(opts)

  @impl true
  def init({opts, registry_key}) do
    mark_loading(registry_key)
    {:ok, %{opts: opts, registry_key: registry_key}, {:continue, :initialize}}
  end

  @impl true
  def handle_continue(:initialize, state) do
    case rebuild(state.opts, state.registry_key) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Jido Discovery did not refresh: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:registry, _from, state) do
    {:reply, registry_result(state.registry_key), state}
  end

  def handle_call({:refresh, opts}, _from, state) do
    {:reply, rebuild(opts, state.registry_key), state}
  end

  defp rebuild(opts, registry_key) do
    previous = :persistent_term.get(registry_key, :not_initialized)
    mark_loading(registry_key)

    with {:ok, modules, provider_timeout_ms} <- discovery_modules(opts),
         {:ok, registry} <- build_registry(modules, provider_timeout_ms) do
      :persistent_term.put(registry_key, registry)
      :ok
    else
      {:error, reason} = error ->
        retain_registry_or_error(registry_key, previous, reason)
        error
    end
  end

  defp mark_loading(registry_key) do
    unless match?(%Registry{}, :persistent_term.get(registry_key, :not_initialized)) do
      :persistent_term.put(registry_key, :loading)
    end
  end

  defp retain_registry_or_error(registry_key, %Registry{} = registry, _reason),
    do: :persistent_term.put(registry_key, registry)

  defp retain_registry_or_error(registry_key, _previous, reason),
    do: :persistent_term.put(registry_key, {:error, reason})

  defp registry_result(registry_key) do
    case :persistent_term.get(registry_key, :not_initialized) do
      %Registry{} = registry -> {:ok, registry}
      {:error, reason} -> {:error, {:initialization_failed, reason}}
    end
  end

  defp unwrap_registry({:ok, %Registry{} = registry}), do: registry

  defp unwrap_registry({:error, {:initialization_failed, reason}}),
    do: raise_registry_initialization_failed(reason)

  defp raise_registry_not_initialized do
    raise Jido.Authoring.Error.internal(
            :registry_not_initialized,
            "authoring Registry is not initialized"
          )
  end

  defp raise_registry_initialization_failed(reason) do
    raise Jido.Authoring.Error.internal(
            :registry_initialization_failed,
            "authoring Registry initialization failed: #{inspect(reason)}",
            %{reason: reason}
          )
  end

  defp discovery_modules(opts) do
    with {:ok, opts} <- validate_options(opts, :invalid_discovery_options),
         {:ok, config} <- discovery_config(),
         {:ok, applications} <- application_option(opts, config),
         {:ok, configured_modules} <- module_option(config),
         {:ok, option_modules} <- module_option(opts),
         {:ok, provider_timeout_ms} <- provider_timeout_option(opts, config),
         {:ok, application_modules} <- modules_for_applications(applications) do
      modules =
        application_modules
        |> Kernel.++(configured_modules)
        |> Kernel.++(option_modules)
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, modules, provider_timeout_ms}
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

  defp provider_timeout_option(opts, config) do
    value =
      Keyword.get(
        opts,
        :provider_timeout_ms,
        Keyword.get(config, :provider_timeout_ms, @default_provider_timeout_ms)
      )

    if is_integer(value) and value > 0,
      do: {:ok, value},
      else: {:error, {:invalid_provider_timeout_ms, value}}
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

  defp build_registry(modules, provider_timeout_ms) do
    with {:ok, {entries, codecs}} <-
           Enum.reduce_while(modules, {:ok, {[], []}}, fn module, {:ok, {entries, codecs}} ->
             case discover_isolated(module, provider_timeout_ms) do
               {:ok, found_entries, found_codecs} ->
                 {:cont, {:ok, {found_entries ++ entries, found_codecs ++ codecs}}}

               {:error, error} ->
                 {:halt, {:error, error}}
             end
           end) do
      Registry.new_discovered(entries, codecs)
    end
  end

  defp discover_isolated(module, timeout_ms) do
    owner = self()
    result_tag = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        send(owner, {result_tag, discover(module)})
      end)

    receive do
      {^result_tag, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        {:error, {:authoring_provider_failed, module, reason}}
    after
      timeout_ms ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
        end

        {:error, {:authoring_provider_timeout, module, timeout_ms}}
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
    if function_exported?(module, :__jido_authoring__, 0) do
      with {:ok, entries} <- Manifest.validate(module, module.__jido_authoring__()) do
        {:ok, Enum.map(entries, &decorate_entry/1)}
      end
    else
      {:ok, []}
    end
  rescue
    error -> {:error, {:authoring_manifest_failed, module, error}}
  catch
    kind, reason -> {:error, {:authoring_manifest_failed, module, {kind, reason}}}
  end

  defp codec_metadata(module) do
    if function_exported?(module, :__jido_authoring_codec__, 0) do
      case Codec.metadata(module) do
        {:ok, metadata} ->
          {:ok, [Map.put(metadata, :module, module)]}

        {:error, {:metadata_failure, kind, reason}} ->
          {:error, {:authoring_codec_failed, module, {kind, reason}}}

        {:error, {:invalid_metadata, metadata}} ->
          {:error, {:invalid_authoring_codec, module, metadata}}

        {:error, :invalid_contract} ->
          {:error, {:invalid_authoring_codec, module, :invalid_contract}}
      end
    else
      {:ok, []}
    end
  end

  defp decorate_entry(entry) do
    Map.put(entry, :application, Application.get_application(entry.provider))
  end
end
