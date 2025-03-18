defmodule Jido.Discovery do
  @moduledoc """
  The Discovery module is Jido's component registry system, providing efficient caching and lookup
  of system components like Actions, Sensors, Agents, and Skills. Think of it as a "service registry"
  that helps different parts of your system find and interact with each other.

  ## Core Concepts

  ### Component Discovery

  Discovery works by scanning all loaded applications for components that implement Jido's
  metadata protocols. It automatically finds and indexes:

  - **Actions** - Discrete units of work
  - **Sensors** - Event monitoring components
  - **Agents** - Autonomous workers
  - **Skills** - Reusable capability packs
  - **Demos** - Example implementations - used in the Jido Workbench (https://github.com/agentjido/jido_workbench)

  The module uses Erlang's `:persistent_term` for optimal lookup performance

  ### Component Metadata

  Each discovered component includes the following metadata:

  ```elixir
  %{
    module: MyApp.CoolAction,        # The actual module
    name: "cool_action",            # Human-readable name
    description: "Does cool stuff", # What it does
    slug: "abc123de",              # Unique identifier
    category: :utility,            # Broad classification
    tags: [:cool, :stuff]          # Searchable tags
  }
  ```

  ## Usage Examples

  ### Basic Component Lookup

  Find components by their unique slugs:

  ```elixir
  # Find a specific action
  case Discovery.get_action_by_slug("abc123de") do
    %{module: module} ->
      # Use the action module
      {:ok, result} = module.run()
    nil ->
      # Handle missing action
  end

  # Find a sensor
  sensor = Discovery.get_sensor_by_slug("def456gh")
  ```

  ### Filtered Component Lists

  Get filtered lists of components:

  ```elixir
  # List all monitoring sensors
  sensors = Discovery.list_sensors(
    category: :monitoring,
    tag: :metrics
  )

  # Get the first 10 utility actions
  actions = Discovery.list_actions(
    category: :utility,
    limit: 10
  )

  # Search agents by name
  agents = Discovery.list_agents(
    name: "processor",
    offset: 5,
    limit: 5
  )
  ```

  ### Cache Management

  Control the discovery cache lifecycle:

  ```elixir
  # Initialize cache (usually done at startup)
  :ok = Discovery.init()

  # Force cache refresh if needed
  :ok = Discovery.refresh()

  # Check last update time
  {:ok, last_updated} = Discovery.last_updated()
  ```

  ## Component Registration

  Components are automatically discovered when they:
  1. Are loaded in any application in the system
  2. Implement the appropriate metadata callback
  3. Include required metadata fields

  Example component:
  ```elixir
  defmodule MyApp.CoolAction do
    use Jido.Action,
      name: "cool_action",
      description: "Does cool stuff",
      category: :utility,
      tags: [:cool, :stuff]

    # Metadata is automatically generated from use params
    # def __action_metadata__ do
    #   %{
    #     name: "cool_action",
    #     description: "Does cool stuff",
    #     category: :utility,
    #     tags: [:cool, :stuff]
    #   }
    # end
  end
  ```

  ## Cache Structure

  The discovery cache maintains separate collections for each component type:

  ```elixir
  %{
    version: "1.0",              # Cache format version
    last_updated: ~U[...],       # Last refresh timestamp
    actions: [...],              # List of actions
    sensors: [...],              # List of sensors
    agents: [...],               # List of agents
    skills: [...],              # List of skills
    demos: [...]                # List of demos
  }
  ```

  ## Filtering Options

  All list functions support these filters:

  - `:limit` - Maximum results to return
  - `:offset` - Results to skip (pagination)
  - `:name` - Filter by name (partial match)
  - `:description` - Filter by description (partial match)
  - `:category` - Filter by category (exact match)
  - `:tag` - Filter by tag (must have exact tag)

  ## Important Notes

  - Cache is shared across all processes
  - Components must be loaded before discovery
  - Metadata changes require cache refresh
  - Slug generation is deterministic
  - Filter options are additive (AND logic)

  ## See Also

  - `Jido.Action` - Action component behavior
  - `Jido.Sensor` - Sensor component behavior
  - `Jido.Agent` - Agent component behavior
  - `Jido.Skill` - Skill component behavior
  """
  require Logger

  @cache_key :__jido_discovery_cache__
  @cache_version "1.0"

  @type component_type :: :action | :sensor | :agent | :skill | :demo
  @type component_metadata :: %{
          module: module(),
          name: String.t(),
          description: String.t(),
          slug: String.t(),
          category: atom() | nil,
          tags: [atom()] | nil
        }

  @type cache_entry :: %{
          version: String.t(),
          last_updated: DateTime.t(),
          actions: [component_metadata()],
          sensors: [component_metadata()],
          agents: [component_metadata()],
          skills: [component_metadata()],
          demos: [component_metadata()]
        }

  @doc """
  Initializes the discovery cache. Should be called during application startup.

  ## Returns

  - `:ok` if cache was initialized successfully
  - `{:error, reason}` if initialization failed
  """
  @spec init() :: :ok | {:error, term()}
  def init do
    try do
      cache = build_cache()
      :persistent_term.put(@cache_key, cache)
      Logger.debug("[Jido.Discovery] Jido cache initialized successfully")
      :ok
    rescue
      e ->
        Logger.warning("[Jido.Discovery] Failed to initialize discovery cache: #{inspect(e)}")
        {:error, :cache_init_failed}
    end
  end

  @doc """
  Forces a refresh of the discovery cache.

  ## Returns

  - `:ok` if cache was refreshed successfully
  - `{:error, reason}` if refresh failed
  """
  @spec refresh() :: :ok | {:error, term()}
  def refresh do
    try do
      cache = build_cache()
      :persistent_term.put(@cache_key, cache)
      Logger.info("Jido discovery cache refreshed successfully")
      :ok
    rescue
      e ->
        Logger.warning("Failed to refresh Jido discovery cache: #{inspect(e)}")
        {:error, :cache_refresh_failed}
    end
  end

  @doc """
  Gets the last time the cache was updated.

  ## Returns

  - `{:ok, datetime}` with the last update time
  - `{:error, :not_initialized}` if cache hasn't been initialized
  """
  @spec last_updated() :: {:ok, DateTime.t()} | {:error, :not_initialized}
  def last_updated do
    case get_cache() do
      {:ok, cache} -> {:ok, cache.last_updated}
      error -> error
    end
  end

  @doc """
  Retrieves an Action by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Action.

  ## Returns

  The Action metadata if found, otherwise `nil`.

  ## Examples

      iex> Jido.get_action_by_slug("abc123de")
      %{module: MyApp.SomeAction, name: "some_action", description: "Does something", slug: "abc123de"}

      iex> Jido.get_action_by_slug("nonexistent")
      nil

  """
  @spec get_action_by_slug(String.t()) :: component_metadata() | nil
  def get_action_by_slug(slug) do
    case get_cache() do
      {:ok, cache} -> Enum.find(cache.actions, fn action -> action.slug == slug end)
      _ -> nil
    end
  end

  @doc """
  Retrieves a Sensor by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Sensor.

  ## Returns

  The Sensor metadata if found, otherwise `nil`.

  ## Examples
      iex> Jido.get_sensor_by_slug("def456gh")
      %{module: MyApp.SomeSensor, name: "some_sensor", description: "Monitors something", slug: "def456gh"}

      iex> Jido.get_sensor_by_slug("nonexistent")
      nil

  """
  @spec get_sensor_by_slug(String.t()) :: component_metadata() | nil
  def get_sensor_by_slug(slug) do
    case get_cache() do
      {:ok, cache} -> Enum.find(cache.sensors, fn sensor -> sensor.slug == slug end)
      _ -> nil
    end
  end

  @doc """
  Retrieves an Agent by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Agent.

  ## Returns

  The Agent metadata if found, otherwise `nil`.

  ## Examples

      iex> Jido.get_agent_by_slug("ghi789jk")
      %{module: MyApp.SomeAgent, name: "some_agent", description: "Represents an agent", slug: "ghi789jk"}

      iex> Jido.get_agent_by_slug("nonexistent")
      nil

  """
  @spec get_agent_by_slug(String.t()) :: component_metadata() | nil
  def get_agent_by_slug(slug) do
    case get_cache() do
      {:ok, cache} -> Enum.find(cache.agents, fn agent -> agent.slug == slug end)
      _ -> nil
    end
  end

  @doc """
  Retrieves a Skill by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Skill.

  ## Returns

  The Skill metadata if found, otherwise `nil`.

  ## Examples

      iex> Jido.get_skill_by_slug("jkl012mn")
      %{module: MyApp.SomeSkill, name: "some_skill", description: "Provides some capability", slug: "jkl012mn"}

      iex> Jido.get_skill_by_slug("nonexistent")
      nil

  """
  @spec get_skill_by_slug(String.t()) :: component_metadata() | nil
  def get_skill_by_slug(slug) do
    case get_cache() do
      {:ok, cache} -> Enum.find(cache.skills, fn skill -> skill.slug == slug end)
      _ -> nil
    end
  end

  @doc """
  Retrieves a Demo by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Demo.

  ## Returns

  The Demo metadata if found, otherwise `nil`.

  ## Examples

      iex> Jido.get_demo_by_slug("mno345pq")
      %{module: MyApp.SomeDemo, name: "some_demo", description: "Demonstrates something", slug: "mno345pq"}

      iex> Jido.get_demo_by_slug("nonexistent")
      nil

  """
  @spec get_demo_by_slug(String.t()) :: component_metadata() | nil
  def get_demo_by_slug(slug) do
    case get_cache() do
      {:ok, cache} -> Enum.find(cache.demos, fn demo -> demo.slug == slug end)
      _ -> nil
    end
  end

  @doc """
  Lists all Actions with optional filtering and pagination.

  ## Parameters

  - `opts`: A keyword list of options for filtering and pagination. Available options:
    - `:limit`: Maximum number of results to return.
    - `:offset`: Number of results to skip before starting to return.
    - `:name`: Filter Actions by name (partial match).
    - `:description`: Filter Actions by description (partial match).
    - `:category`: Filter Actions by category (exact match).
    - `:tag`: Filter Actions by tag (must have the exact tag).

  ## Returns

  A list of Action metadata.

  ## Examples

      iex> Jido.list_actions(limit: 10, offset: 5, category: :utility)
      [%{module: MyApp.SomeAction, name: "some_action", description: "Does something", slug: "abc123de", category: :utility}]

  """
  @spec list_actions(keyword()) :: [component_metadata()]
  def list_actions(opts \\ []) do
    case get_cache() do
      {:ok, cache} -> filter_and_paginate(cache.actions, opts)
      _ -> []
    end
  end

  @doc """
  Lists all Sensors with optional filtering and pagination.

  ## Parameters

  - `opts`: A keyword list of options for filtering and pagination. Available options:
    - `:limit`: Maximum number of results to return.
    - `:offset`: Number of results to skip before starting to return.
    - `:name`: Filter Sensors by name (partial match).
    - `:description`: Filter Sensors by description (partial match).
    - `:category`: Filter Sensors by category (exact match).
    - `:tag`: Filter Sensors by tag (must have the exact tag).

  ## Returns

  A list of Sensor metadata.

  ## Examples

      iex> Jido.list_sensors(limit: 10, offset: 5, category: :monitoring)
      [%{module: MyApp.SomeSensor, name: "some_sensor", description: "Monitors something", slug: "def456gh", category: :monitoring}]

  """
  @spec list_sensors(keyword()) :: [component_metadata()]
  def list_sensors(opts \\ []) do
    case get_cache() do
      {:ok, cache} -> filter_and_paginate(cache.sensors, opts)
      _ -> []
    end
  end

  @doc """
  Lists all Agents with optional filtering and pagination.

  ## Parameters

  - `opts`: A keyword list of options for filtering and pagination. Available options:
    - `:limit`: Maximum number of results to return.
    - `:offset`: Number of results to skip before starting to return.
    - `:name`: Filter Agents by name (partial match).
    - `:description`: Filter Agents by description (partial match).
    - `:category`: Filter Agents by category (exact match).
    - `:tag`: Filter Agents by tag (must have the exact tag).

  ## Returns

  A list of Agent metadata.

  ## Examples

      iex> Jido.list_agents(limit: 10, offset: 5, category: :business)
      [%{module: MyApp.SomeAgent, name: "some_agent", description: "Represents an agent", slug: "ghi789jk", category: :business}]

  """
  @spec list_agents(keyword()) :: [component_metadata()]
  def list_agents(opts \\ []) do
    case get_cache() do
      {:ok, cache} -> filter_and_paginate(cache.agents, opts)
      _ -> []
    end
  end

  @doc """
  Lists all Skills with optional filtering and pagination.

  ## Parameters

  - `opts`: A keyword list of options for filtering and pagination. Available options:
    - `:limit`: Maximum number of results to return.
    - `:offset`: Number of results to skip before starting to return.
    - `:name`: Filter Skills by name (partial match).
    - `:description`: Filter Skills by description (partial match).
    - `:category`: Filter Skills by category (exact match).
    - `:tag`: Filter Skills by tag (must have the exact tag).

  ## Returns

  A list of Skill metadata.

  ## Examples

      iex> Jido.list_skills(limit: 10, offset: 5, category: :capability)
      [%{module: MyApp.SomeSkill, name: "some_skill", description: "Provides some capability", slug: "jkl012mn", category: :capability}]

  """
  @spec list_skills(keyword()) :: [component_metadata()]
  def list_skills(opts \\ []) do
    case get_cache() do
      {:ok, cache} -> filter_and_paginate(cache.skills, opts)
      _ -> []
    end
  end

  @doc """
  Lists all Demos with optional filtering and pagination.

  ## Parameters

  - `opts`: A keyword list of options for filtering and pagination. Available options:
    - `:limit`: Maximum number of results to return.
    - `:offset`: Number of results to skip before starting to return.
    - `:name`: Filter Demos by name (partial match).
    - `:description`: Filter Demos by description (partial match).
    - `:category`: Filter Demos by category (exact match).
    - `:tag`: Filter Demos by tag (must have the exact tag).

  ## Returns

  A list of Demo metadata.

  ## Examples

      iex> Jido.list_demos(limit: 10, offset: 5, category: :example)
      [%{module: MyApp.SomeDemo, name: "some_demo", description: "Demonstrates something", slug: "mno345pq", category: :example}]

  """
  @spec list_demos(keyword()) :: [component_metadata()]
  def list_demos(opts \\ []) do
    case get_cache() do
      {:ok, cache} -> filter_and_paginate(cache.demos, opts)
      _ -> []
    end
  end

  @doc false
  def __get_cache__, do: get_cache()

  # Private functions
  defp get_cache do
    try do
      case :persistent_term.get(@cache_key) do
        %{version: @cache_version} = cache -> {:ok, cache}
        _ -> {:error, :invalid_cache_version}
      end
    rescue
      ArgumentError -> {:error, :not_initialized}
    end
  end

  defp build_cache do
    %{
      version: @cache_version,
      last_updated: DateTime.utc_now(),
      actions: discover_components(:__action_metadata__),
      sensors: discover_components(:__sensor_metadata__),
      agents: discover_components(:__agent_metadata__),
      skills: discover_components(:__skill_metadata__),
      demos: discover_components(:__jido_demo__)
    }
  end

  defp discover_components(metadata_function) do
    all_applications()
    |> Enum.flat_map(&all_modules/1)
    |> Enum.filter(&has_metadata_function?(&1, metadata_function))
    |> Enum.map(fn module ->
      metadata = apply(module, metadata_function, [])
      module_name = to_string(module)

      slug =
        :sha256
        |> :crypto.hash(module_name)
        |> Base.url_encode64(padding: false)
        |> String.slice(0, 8)

      metadata = if Keyword.keyword?(metadata), do: Map.new(metadata), else: metadata

      metadata
      |> Map.put(:module, module)
      |> Map.put(:slug, slug)
    end)
  end

  defp filter_and_paginate(components, opts) do
    components
    |> filter_components(opts)
    |> paginate(opts)
  end

  defp filter_components(components, opts) do
    name = Keyword.get(opts, :name)
    description = Keyword.get(opts, :description)
    category = Keyword.get(opts, :category)
    tag = Keyword.get(opts, :tag)

    Enum.filter(components, fn metadata ->
      matches_name?(metadata, name) and
        matches_description?(metadata, description) and
        matches_category?(metadata, category) and
        matches_tag?(metadata, tag)
    end)
  end

  defp paginate(components, opts) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit)

    components
    |> Enum.drop(offset)
    |> maybe_limit(limit)
  end

  defp all_applications,
    do: Application.loaded_applications() |> Enum.map(fn {app, _, _} -> app end)

  defp all_modules(app) do
    case :application.get_key(app, :modules) do
      {:ok, modules} -> modules
      :undefined -> []
    end
  end

  defp has_metadata_function?(module, function) do
    Code.ensure_loaded?(module) and function_exported?(module, function, 0)
  end

  defp matches_name?(_metadata, nil), do: true
  defp matches_name?(metadata, name), do: String.contains?(metadata[:name] || "", name)

  defp matches_description?(_metadata, nil), do: true

  defp matches_description?(metadata, description),
    do: String.contains?(metadata[:description] || "", description)

  defp matches_category?(_metadata, nil), do: true
  defp matches_category?(metadata, category), do: metadata[:category] == category

  defp matches_tag?(_metadata, nil), do: true
  defp matches_tag?(metadata, tag), do: is_list(metadata[:tags]) and tag in metadata[:tags]

  defp maybe_limit(list, nil), do: list
  defp maybe_limit(list, limit) when is_integer(limit) and limit > 0, do: Enum.take(list, limit)
  defp maybe_limit(list, _), do: list
end
