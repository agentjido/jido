defmodule Jido.Discovery do
  @moduledoc """
  Builds a read-only catalog of available Action modules.

  Jido starts one temporary Task that builds the catalog after startup. The
  Task scans the module lists of loaded applications. You can also configure
  an application allowlist or add modules that are not in an application.

      config :jido, Jido.Discovery,
        applications: [:my_app, :jido_connect_github],
        modules: [MyApp.SpecialAction]

  The default application value is `:loaded`. This value scans all loaded
  applications. `refresh/1` replaces the complete catalog. Reads use
  `:persistent_term` and do not call Action code.

  Discovery is an inventory service. It does not grant permission to run an
  Action. A product must keep its own allowlist and assignment data.

  Inline Actions are implementation details of their owner modules. Discovery
  does not add them to the catalog.
  """

  require Logger

  alias Jido.Executable

  @catalog_key {__MODULE__, :catalog}
  @catalog_version 1
  @default_applications :loaded

  @typedoc "Metadata for one discovered Action."
  @type action_metadata :: %{
          module: module(),
          application: atom() | nil,
          name: String.t(),
          description: String.t() | nil,
          slug: String.t()
        }

  @typedoc "A module that looked like an Action but did not have a valid contract."
  @type diagnostic :: %{module: module(), error: term()}

  @typedoc "The immutable Discovery catalog."
  @type catalog :: %{
          version: pos_integer(),
          built_at: DateTime.t(),
          actions: [action_metadata()],
          diagnostics: [diagnostic()],
          actions_by_module: %{optional(module()) => action_metadata()},
          actions_by_slug: %{optional(String.t()) => action_metadata()}
        }

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {Task, :start_link, [fn -> initialize(opts) end]},
      restart: :temporary,
      type: :worker
    }
  end

  @doc "Returns true when the first catalog build is complete."
  @spec ready?() :: boolean()
  def ready?, do: :persistent_term.get(@catalog_key, :not_initialized) != :not_initialized

  @doc "Returns the complete catalog."
  @spec catalog() :: {:ok, catalog()} | {:error, :not_initialized}
  def catalog do
    case :persistent_term.get(@catalog_key, :not_initialized) do
      :not_initialized -> {:error, :not_initialized}
      catalog -> {:ok, catalog}
    end
  end

  @doc "Returns the time of the last successful catalog build."
  @spec last_updated() :: {:ok, DateTime.t()} | {:error, :not_initialized}
  def last_updated do
    with {:ok, catalog} <- catalog() do
      {:ok, catalog.built_at}
    end
  end

  @doc """
  Lists discovered Actions.

  Use `:name` and `:description` for case-sensitive partial matches. Use
  `:application` for an exact match. Use `:offset` and `:limit` for paging.
  """
  @spec list_actions(keyword()) :: [action_metadata()]
  def list_actions(opts \\ []) do
    case catalog() do
      {:ok, catalog} -> filter_and_paginate(catalog.actions, opts)
      {:error, :not_initialized} -> []
    end
  end

  @doc "Returns a discovered Action for a module."
  @spec get_action(module()) :: action_metadata() | nil
  def get_action(module) when is_atom(module) do
    case catalog() do
      {:ok, catalog} -> Map.get(catalog.actions_by_module, module)
      {:error, :not_initialized} -> nil
    end
  end

  @doc "Returns a discovered Action for a catalog slug."
  @spec get_action_by_slug(String.t()) :: action_metadata() | nil
  def get_action_by_slug(slug) when is_binary(slug) do
    case catalog() do
      {:ok, catalog} -> Map.get(catalog.actions_by_slug, slug)
      {:error, :not_initialized} -> nil
    end
  end

  @doc """
  Rebuilds and replaces the complete catalog.

  `:applications` defaults to the configured value or `:loaded`. `:modules`
  adds explicit modules to the application scan. Pass `applications: []` to
  scan only explicit modules.
  """
  @spec refresh(keyword()) :: :ok | {:error, term()}
  def refresh(opts \\ []) do
    with {:ok, modules} <- discovery_modules(opts),
         {:ok, catalog} <- build_catalog(modules) do
      :persistent_term.put(@catalog_key, catalog)
      :ok
    end
  end

  defp initialize(opts) do
    case refresh(opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Jido Discovery did not build its catalog: #{inspect(reason)}")
        :ok
    end
  end

  defp discovery_modules(opts) do
    with {:ok, config} <- discovery_config(),
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
      config when is_list(config) -> {:ok, config}
      config -> {:error, {:invalid_discovery_config, config}}
    end
  end

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

  defp validate_atoms(_name, values) when values == [], do: {:ok, []}

  defp validate_atoms(name, values) do
    if Enum.all?(values, &(is_atom(&1) and not is_nil(&1))) do
      {:ok, values}
    else
      invalid_atom_list(name, values)
    end
  end

  defp invalid_atom_list(:applications, values), do: {:error, {:invalid_applications, values}}
  defp invalid_atom_list(:modules, values), do: {:error, {:invalid_modules, values}}

  defp loaded_applications do
    Application.loaded_applications()
    |> Enum.map(&elem(&1, 0))
  end

  defp modules_for_applications(applications) do
    Enum.reduce_while(applications, {:ok, []}, fn application, {:ok, result} ->
      case Application.spec(application, :modules) do
        modules when is_list(modules) -> {:cont, {:ok, modules ++ result}}
        nil -> {:halt, {:error, {:application_not_loaded, application}}}
      end
    end)
  end

  defp build_catalog(modules) do
    {actions, diagnostics} =
      Enum.reduce(modules, {[], []}, fn module, {actions, diagnostics} ->
        case discover_action(module) do
          {:ok, metadata} -> {[metadata | actions], diagnostics}
          :skip -> {actions, diagnostics}
          {:error, error} -> {actions, [%{module: module, error: error} | diagnostics]}
        end
      end)

    actions = Enum.sort_by(actions, &{&1.name, Atom.to_string(&1.module)})
    diagnostics = Enum.sort_by(diagnostics, &Atom.to_string(&1.module))

    with :ok <- validate_unique_slugs(actions) do
      {:ok,
       %{
         version: @catalog_version,
         built_at: DateTime.utc_now(),
         actions: actions,
         diagnostics: diagnostics,
         actions_by_module: Map.new(actions, &{&1.module, &1}),
         actions_by_slug: Map.new(actions, &{&1.slug, &1})
       }}
    end
  end

  defp discover_action(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> discover_loaded_action(module)
      {:error, reason} -> {:error, {:module_not_loaded, reason}}
    end
  end

  defp discover_loaded_action(module) do
    cond do
      function_exported?(module, :__jido_inline_action__, 0) ->
        :skip

      not function_exported?(module, :__jido_executable__, 0) ->
        :skip

      true ->
        validate_action(module)
    end
  end

  defp validate_action(module) do
    with {:ok, %Executable{kind: :action, target: ^module} = executable} <-
           Executable.resolve(module),
         :ok <- Executable.validate(executable),
         {:ok, metadata} <- action_metadata(module) do
      {:ok, metadata}
    else
      {:ok, %Executable{}} -> :skip
      {:error, error} -> {:error, error}
    end
  end

  defp action_metadata(module) do
    name = module.name()
    description = module.description()

    if is_binary(name) and (is_binary(description) or is_nil(description)) do
      {:ok,
       %{
         module: module,
         application: Application.get_application(module),
         name: name,
         description: description,
         slug: slug(module)
       }}
    else
      {:error, {:invalid_action_metadata, %{name: name, description: description}}}
    end
  rescue
    error -> {:error, {:action_metadata_failed, error}}
  catch
    kind, reason -> {:error, {:action_metadata_failed, {kind, reason}}}
  end

  defp slug(module) do
    module
    |> Atom.to_string()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 16)
  end

  defp validate_unique_slugs(actions) do
    case Enum.find(Enum.group_by(actions, & &1.slug), fn {_slug, items} -> length(items) > 1 end) do
      nil -> :ok
      {slug, items} -> {:error, {:duplicate_action_slug, slug, Enum.map(items, & &1.module)}}
    end
  end

  defp filter_and_paginate(actions, opts) do
    name = Keyword.get(opts, :name)
    description = Keyword.get(opts, :description)
    application = Keyword.get(opts, :application)
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit)

    actions
    |> Enum.filter(fn metadata ->
      contains?(metadata.name, name) and
        contains?(metadata.description, description) and
        matches?(metadata.application, application)
    end)
    |> Enum.drop(valid_offset(offset))
    |> maybe_limit(limit)
  end

  defp contains?(_value, nil), do: true
  defp contains?(nil, _part), do: false
  defp contains?(value, part) when is_binary(part), do: String.contains?(value, part)
  defp contains?(_value, _part), do: false

  defp matches?(_value, nil), do: true
  defp matches?(value, expected), do: value == expected

  defp valid_offset(offset) when is_integer(offset) and offset >= 0, do: offset
  defp valid_offset(_offset), do: 0

  defp maybe_limit(actions, limit) when is_integer(limit) and limit >= 0,
    do: Enum.take(actions, limit)

  defp maybe_limit(actions, _limit), do: actions
end
