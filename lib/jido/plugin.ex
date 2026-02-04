defmodule Jido.Plugin do
  @moduledoc """
  A Plugin is a composable capability that can be attached to an agent.

  Plugins encapsulate:
  - A set of actions the agent can perform
  - State schema for plugin-specific data (nested under `state_key`)
  - Configuration schema for per-agent customization
  - Signal routing rules
  - Optional lifecycle hooks and child processes

  ## Lifecycle

  1. **Compile-time**: Plugin is declared in agent's `plugins:` option
  2. **Agent.new/1**: `mount/2` is called to initialize plugin state (pure)
  3. **AgentServer.init/1**: `child_spec/1` processes are started and monitored
  4. **Signal processing**: `handle_signal/2` runs before routing, can override or abort
  5. **After cmd/2 (call path)**: `transform_result/3` wraps call results

  ## Example Plugin

      defmodule MyApp.ChatPlugin do
        use Jido.Plugin,
          name: "chat",
          state_key: :chat,
          actions: [MyApp.Actions.SendMessage, MyApp.Actions.ListHistory],
          schema: Zoi.object(%{
            messages: Zoi.list(Zoi.any()) |> Zoi.default([]),
            model: Zoi.string() |> Zoi.default("gpt-4")
          }),
          signal_patterns: ["chat.*"]

        @impl Jido.Plugin
        def mount(agent, config) do
          # Custom initialization beyond schema defaults
          {:ok, %{initialized_at: DateTime.utc_now()}}
        end

        @impl Jido.Plugin
        def router(config) do
          [
            {"chat.send", MyApp.Actions.SendMessage},
            {"chat.history", MyApp.Actions.ListHistory}
          ]
        end
      end

  ## Using Plugins

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          plugins: [
            MyApp.ChatPlugin,
            {MyApp.DatabasePlugin, %{pool_size: 5}}
          ]
      end

  ## Configuration Options

  - `name` - Required. The plugin name (letters, numbers, underscores).
  - `state_key` - Required. Atom key for plugin state in agent.
  - `actions` - Required. List of action modules.
  - `description` - Optional description.
  - `category` - Optional category.
  - `vsn` - Optional version string.
  - `schema` - Optional Zoi schema for plugin state.
  - `config_schema` - Optional Zoi schema for per-agent config.
  - `signal_patterns` - List of signal pattern strings (default: []).
  - `tags` - List of tag strings (default: []).
  - `capabilities` - List of atoms describing what the plugin provides (default: []).
  - `requires` - List of requirements like `{:config, :token}`, `{:app, :req}`, `{:plugin, :http}` (default: []).
  - `routes` - List of route tuples like `{"post", ActionModule}` (default: []).
  - `schedules` - List of schedule tuples like `{"*/5 * * * *", ActionModule}` (default: []).
  """

  alias Jido.Plugin.Manifest
  alias Jido.Plugin.Spec

  @plugin_config_schema Zoi.object(
                          %{
                            name:
                              Zoi.string(
                                description:
                                  "The name of the Plugin. Must contain only letters, numbers, and underscores."
                              )
                              |> Zoi.refine({Jido.Util, :validate_name, []}),
                            state_key:
                              Zoi.atom(description: "The key for plugin state in agent state."),
                            actions:
                              Zoi.list(Zoi.atom(), description: "List of action modules.")
                              |> Zoi.refine({Jido.Util, :validate_actions, []}),
                            description:
                              Zoi.string(description: "A description of what the Plugin does.")
                              |> Zoi.optional(),
                            category:
                              Zoi.string(description: "The category of the Plugin.")
                              |> Zoi.optional(),
                            vsn:
                              Zoi.string(description: "Version")
                              |> Zoi.optional(),
                            otp_app:
                              Zoi.atom(
                                description:
                                  "OTP application for loading config from Application.get_env."
                              )
                              |> Zoi.optional(),
                            schema:
                              Zoi.any(description: "Zoi schema for plugin state.")
                              |> Zoi.optional(),
                            config_schema:
                              Zoi.any(description: "Zoi schema for per-agent configuration.")
                              |> Zoi.optional(),
                            signal_patterns:
                              Zoi.list(Zoi.string(), description: "Signal patterns for routing.")
                              |> Zoi.default([]),
                            tags:
                              Zoi.list(Zoi.string(), description: "Tags for categorization.")
                              |> Zoi.default([]),
                            capabilities:
                              Zoi.list(Zoi.atom(),
                                description: "Capabilities provided by this plugin."
                              )
                              |> Zoi.default([]),
                            requires:
                              Zoi.list(Zoi.any(),
                                description:
                                  "Requirements like {:config, :token}, {:app, :req}, {:plugin, :http}."
                              )
                              |> Zoi.default([]),
                            routes:
                              Zoi.list(Zoi.any(),
                                description: "Route tuples like {\"post\", ActionModule}."
                              )
                              |> Zoi.default([]),
                            schedules:
                              Zoi.list(Zoi.any(),
                                description:
                                  "Schedule tuples like {\"*/5 * * * *\", ActionModule}."
                              )
                              |> Zoi.default([])
                          },
                          coerce: true
                        )

  @doc false
  @spec config_schema() :: Zoi.schema()
  def config_schema, do: @plugin_config_schema

  # Callbacks

  @doc """
  Returns the plugin specification with optional per-agent configuration.

  This is the primary interface for getting plugin metadata and configuration.
  """
  @callback plugin_spec(config :: map()) :: Spec.t()

  @doc """
  Called when the plugin is mounted to an agent during `new/1`.

  Use this to initialize plugin-specific state beyond schema defaults.
  This is a pure function - no side effects allowed.

  ## Parameters

  - `agent` - The agent struct (with state from previously mounted plugins)
  - `config` - Per-agent configuration for this plugin

  ## Returns

  - `{:ok, plugin_state}` - Map to merge into plugin's state slice
  - `{:ok, nil}` - No additional state (schema defaults only)
  - `{:error, reason}` - Raises during agent creation

  ## Example

      def mount(_agent, config) do
        {:ok, %{initialized_at: DateTime.utc_now(), api_key: config[:api_key]}}
      end
  """
  @callback mount(agent :: term(), config :: map()) :: {:ok, map() | nil} | {:error, term()}

  @doc """
  Returns the signal router for this plugin.

  The router determines how signals are routed to handlers.
  """
  @callback router(config :: map()) :: term()

  @doc """
  Pre-routing hook called before signal routing in AgentServer.

  Can inspect, log, or override which action runs for a signal.

  ## Parameters

  - `signal` - The incoming `Jido.Signal` struct
  - `context` - Map with `:agent`, `:agent_module`, `:plugin`, `:plugin_spec`, `:config`

  ## Returns

  - `{:ok, nil}` or `{:ok, :continue}` - Continue to normal routing
  - `{:ok, {:override, action_spec}}` - Bypass router, use this action instead
  - `{:error, reason}` - Abort signal processing with error

  ## Example

      def handle_signal(signal, _context) do
        if signal.type == "admin.override" do
          {:ok, {:override, MyApp.AdminAction}}
        else
          {:ok, :continue}
        end
      end
  """
  @callback handle_signal(signal :: term(), context :: map()) ::
              {:ok, term()} | {:ok, {:override, term()}} | {:error, term()}

  @doc """
  Transform the agent returned from `AgentServer.call/3`.

  Called after signal processing on the synchronous call path only.
  Does not affect `cast/2` or internal state - only the returned agent.

  ## Parameters

  - `action` - The signal type or action module that was executed
  - `result` - The agent struct to transform
  - `context` - Map with `:agent`, `:agent_module`, `:plugin`, `:plugin_spec`, `:config`

  ## Returns

  The transformed agent struct (or original if no transformation needed).

  ## Example

      def transform_result(_action, agent, _context) do
        # Add metadata to returned agent
        new_state = Map.put(agent.state, :last_call_at, DateTime.utc_now())
        %{agent | state: new_state}
      end
  """
  @callback transform_result(action :: module() | String.t(), result :: term(), context :: map()) ::
              term()

  @doc """
  Returns child specification(s) for supervised processes.

  Called during `AgentServer.init/1`. Returned processes are
  started and monitored. If any crash, AgentServer receives exit signals.

  ## Parameters

  - `config` - Per-agent configuration for this plugin

  ## Returns

  - `nil` - No child processes
  - `Supervisor.child_spec()` - Single child
  - `[Supervisor.child_spec()]` - Multiple children

  ## Example

      def child_spec(config) do
        %{
          id: {__MODULE__, :worker},
          start: {MyWorker, :start_link, [config]}
        }
      end
  """
  @callback child_spec(config :: map()) ::
              nil | Supervisor.child_spec() | [Supervisor.child_spec()]

  @doc """
  Returns bus subscriptions for this plugin.

  Called during `AgentServer.init/1` to determine which bus adapters
  to subscribe to and with what options.

  ## Parameters

  - `config` - Per-agent configuration for this plugin
  - `context` - Map with `:agent_id`, `:agent_module`

  ## Returns

  List of `{adapter_module, opts}` tuples. Each adapter's `subscribe/2`
  will be called with the AgentServer pid.

  ## Example

      def subscriptions(_config, context) do
        [
          {Jido.Bus.Adapters.Local, topic: "events.*"},
          {Jido.Bus.Adapters.PubSub, pubsub: MyApp.PubSub, topic: context.agent_id}
        ]
      end
  """
  @callback subscriptions(config :: map(), context :: map()) ::
              [{module(), keyword() | map()}]

  # Macro implementation

  @doc false
  defp generate_behaviour_and_validation(opts) do
    quote location: :keep do
      @behaviour Jido.Plugin

      alias Jido.Plugin.Manifest
      alias Jido.Plugin.Spec

      @validated_opts (case Zoi.parse(Jido.Plugin.config_schema(), Enum.into(unquote(opts), %{})) do
                         {:ok, validated} ->
                           validated

                         {:error, errors} ->
                           raise CompileError,
                             description:
                               "Invalid plugin configuration:\n#{Zoi.prettify_errors(errors)}"
                       end)
    end
  end

  @doc false
  defp generate_accessor_functions do
    [
      generate_core_accessors(),
      generate_optional_accessors(),
      generate_list_accessors()
    ]
  end

  defp generate_core_accessors do
    quote location: :keep do
      @doc "Returns the plugin's name."
      @spec name() :: String.t()
      def name, do: @validated_opts.name

      @doc "Returns the key used to store plugin state in the agent."
      @spec state_key() :: atom()
      def state_key, do: @validated_opts.state_key

      @doc "Returns the list of action modules provided by this plugin."
      @spec actions() :: [module()]
      def actions, do: @validated_opts.actions
    end
  end

  defp generate_optional_accessors do
    quote location: :keep do
      @doc "Returns the plugin's description."
      @spec description() :: String.t() | nil
      def description, do: @validated_opts[:description]

      @doc "Returns the plugin's category."
      @spec category() :: String.t() | nil
      def category, do: @validated_opts[:category]

      @doc "Returns the plugin's version."
      @spec vsn() :: String.t() | nil
      def vsn, do: @validated_opts[:vsn]

      @doc "Returns the OTP application for config resolution."
      @spec otp_app() :: atom() | nil
      def otp_app, do: @validated_opts[:otp_app]

      @doc "Returns the Zoi schema for plugin state."
      @spec schema() :: Zoi.schema() | nil
      def schema, do: @validated_opts[:schema]

      @doc "Returns the Zoi schema for per-agent configuration."
      @spec config_schema() :: Zoi.schema() | nil
      def config_schema, do: @validated_opts[:config_schema]
    end
  end

  defp generate_list_accessors do
    [
      generate_pattern_accessors(),
      generate_requirement_accessors()
    ]
  end

  defp generate_pattern_accessors do
    quote location: :keep do
      @doc "Returns the signal patterns this plugin handles."
      @spec signal_patterns() :: [String.t()]
      def signal_patterns, do: @validated_opts[:signal_patterns] || []

      @doc "Returns the plugin's tags."
      @spec tags() :: [String.t()]
      def tags, do: @validated_opts[:tags] || []

      @doc "Returns the capabilities provided by this plugin."
      @spec capabilities() :: [atom()]
      def capabilities, do: @validated_opts[:capabilities] || []
    end
  end

  defp generate_requirement_accessors do
    quote location: :keep do
      @doc "Returns the requirements for this plugin."
      @spec requires() :: [tuple()]
      def requires, do: @validated_opts[:requires] || []

      @doc "Returns the routes for this plugin."
      @spec routes() :: [tuple()]
      def routes, do: @validated_opts[:routes] || []

      @doc "Returns the schedules for this plugin."
      @spec schedules() :: [tuple()]
      def schedules, do: @validated_opts[:schedules] || []
    end
  end

  @doc false
  defp generate_spec_and_manifest_functions do
    quote location: :keep do
      @doc """
      Returns the plugin specification with optional per-agent configuration.

      ## Examples

          spec = MyModule.plugin_spec(%{})
          spec = MyModule.plugin_spec(%{custom_option: true})
      """
      @spec plugin_spec(map()) :: Spec.t()
      @impl Jido.Plugin
      def plugin_spec(config \\ %{}) do
        %Spec{
          module: __MODULE__,
          name: name(),
          state_key: state_key(),
          description: description(),
          category: category(),
          vsn: vsn(),
          schema: schema(),
          config_schema: config_schema(),
          config: config,
          signal_patterns: signal_patterns(),
          tags: tags(),
          actions: actions()
        }
      end

      @doc """
      Returns the plugin manifest with all metadata.

      The manifest provides compile-time metadata for discovery
      and introspection, including capabilities, requirements,
      routes, and schedules.
      """
      @spec manifest() :: Manifest.t()
      def manifest do
        %Manifest{
          module: __MODULE__,
          name: name(),
          description: description(),
          category: category(),
          tags: tags(),
          vsn: vsn(),
          otp_app: otp_app(),
          capabilities: capabilities(),
          requires: requires(),
          state_key: state_key(),
          schema: schema(),
          config_schema: config_schema(),
          actions: actions(),
          routes: routes(),
          schedules: schedules(),
          signal_patterns: signal_patterns()
        }
      end

      @doc """
      Returns metadata for Jido.Discovery integration.

      This function is used by `Jido.Discovery` to index plugins
      for fast lookup and filtering.
      """
      @spec __plugin_metadata__() :: map()
      def __plugin_metadata__ do
        %{
          name: name(),
          description: description(),
          category: category(),
          tags: tags()
        }
      end
    end
  end

  @doc false
  defp generate_default_callbacks do
    quote location: :keep do
      @doc false
      @spec mount(term(), map()) :: {:ok, map() | nil} | {:error, term()}
      @impl Jido.Plugin
      def mount(_agent, _config), do: {:ok, %{}}

      @doc false
      @spec router(map()) :: term()
      @impl Jido.Plugin
      def router(_config), do: nil

      @doc false
      @spec handle_signal(term(), map()) ::
              {:ok, term()} | {:ok, {:override, term()}} | {:error, term()}
      @impl Jido.Plugin
      def handle_signal(_signal, _context), do: {:ok, nil}

      @doc false
      @spec transform_result(module() | String.t(), term(), map()) :: term()
      @impl Jido.Plugin
      def transform_result(_action, result, _context), do: result

      @doc false
      @spec child_spec(map()) :: nil | Supervisor.child_spec() | [Supervisor.child_spec()]
      @impl Jido.Plugin
      def child_spec(_config), do: nil

      @doc false
      @spec subscriptions(map(), map()) :: [{module(), keyword() | map()}]
      @impl Jido.Plugin
      def subscriptions(_config, _context), do: []
    end
  end

  @doc false
  defp generate_defoverridable do
    quote location: :keep do
      defoverridable mount: 2,
                     router: 1,
                     handle_signal: 2,
                     transform_result: 3,
                     child_spec: 1,
                     subscriptions: 2,
                     name: 0,
                     state_key: 0,
                     actions: 0,
                     description: 0,
                     category: 0,
                     vsn: 0,
                     otp_app: 0,
                     schema: 0,
                     config_schema: 0,
                     signal_patterns: 0,
                     tags: 0,
                     capabilities: 0,
                     requires: 0,
                     routes: 0,
                     schedules: 0
    end
  end

  defmacro __using__(opts) do
    behaviour_and_validation = generate_behaviour_and_validation(opts)
    accessor_functions = generate_accessor_functions()
    spec_and_manifest = generate_spec_and_manifest_functions()
    default_callbacks = generate_default_callbacks()
    defoverridable_block = generate_defoverridable()

    [
      behaviour_and_validation,
      accessor_functions,
      spec_and_manifest,
      default_callbacks,
      defoverridable_block
    ]
  end
end
