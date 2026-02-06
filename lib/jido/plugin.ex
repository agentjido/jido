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
        def signal_routes(_ctx) do
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
  - `signal_routes` - List of signal route tuples like `{"post", ActionModule}` (default: []).
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
                            signal_routes:
                              Zoi.list(Zoi.any(),
                                description: "Signal route tuples like {\"post\", ActionModule}."
                              )
                              |> Zoi.default([]),
                            schedules:
                              Zoi.list(Zoi.any(),
                                description:
                                  "Schedule tuples like {\"*/5 * * * *\", ActionModule}."
                              )
                              |> Zoi.default([]),
                            singleton:
                              Zoi.boolean(
                                description: "If true, plugin cannot be aliased or duplicated."
                              )
                              |> Zoi.default(false)
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
  Returns the signal routes for this plugin.

  The signal routes determine how signals are routed to handlers.
  """
  @callback signal_routes(config :: map()) :: term()

  @doc """
  Pre-routing hook called before signal routing in AgentServer.

  Can inspect, log, transform, or override which action runs for a signal.
  Hooks execute in plugin declaration order. The first `{:override, ...}`
  short-circuits; the first `{:error, ...}` aborts. Plugins with non-empty
  `signal_patterns` only receive signals matching those patterns; plugins
  with empty patterns act as global middleware.

  ## Parameters

  - `signal` - The incoming `Jido.Signal` struct (may be modified by earlier plugins)
  - `context` - Map with `:agent`, `:agent_module`, `:plugin`, `:plugin_spec`,
    `:plugin_instance`, `:config`

  ## Returns

  - `{:ok, nil}` or `{:ok, :continue}` - Continue to normal routing
  - `{:ok, {:continue, %Signal{}}}` - Rewrite the signal and continue routing
  - `{:ok, {:override, action_spec}}` - Bypass router, use this action instead
  - `{:ok, {:override, action_spec, %Signal{}}}` - Bypass router with rewritten signal
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
  Caller view transform for the agent returned from `AgentServer.call/3`.

  Called after signal processing on the **synchronous call path only**.
  Does not affect `cast/2`, `handle_info`, or internal server state — only
  the agent struct returned to the caller. Transforms chain through all
  plugins in declaration order.

  ## Parameters

  - `action` - The resolved action module that was executed, or the signal
    type string when no single module can be determined
  - `result` - The agent struct to transform
  - `context` - Map with `:agent`, `:agent_module`, `:plugin`, `:plugin_spec`,
    `:plugin_instance`, `:config`

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

  @doc """
  Called during checkpoint to determine how this plugin's state should be persisted.

  Plugins can declare one of three strategies for their state slice:

  - `:keep` — Include in checkpoint state as-is (default)
  - `:drop` — Exclude from checkpoint (transient/ephemeral state)
  - `{:externalize, key, pointer}` — Strip from checkpoint state and store a
    pointer separately. The pointer is a lightweight reference (e.g., `%{id, rev}`)
    that can be used to rehydrate the full state on restore.

  ## Parameters

  - `plugin_state` - The plugin's current state slice (may be nil)
  - `context` - Map with checkpoint context (e.g., `:config`)

  ## Returns

  - `:keep` — Include plugin state in checkpoint (default)
  - `:drop` — Exclude from checkpoint
  - `{:externalize, key, pointer}` — Store pointer under `key` in checkpoint

  ## Example

      def on_checkpoint(%Thread{} = thread, _ctx) do
        {:externalize, :thread, %{id: thread.id, rev: thread.rev}}
      end

      def on_checkpoint(nil, _ctx), do: :keep
  """
  @callback on_checkpoint(plugin_state :: term(), context :: map()) ::
              {:externalize, key :: atom(), pointer :: term()} | :keep | :drop

  @doc """
  Called during restore to rehydrate externalized plugin state.

  When a plugin's `on_checkpoint/2` returns `{:externalize, key, pointer}`,
  the pointer is stored in the checkpoint. During restore, `on_restore/2`
  is called with that pointer to allow the plugin to reconstruct its state.

  For plugins that require IO to restore (e.g., loading a thread from storage),
  returning `{:ok, nil}` signals that the state will be rehydrated by the
  persistence layer (e.g., `Jido.Persist`).

  ## Parameters

  - `pointer` - The pointer stored during checkpoint (from `on_checkpoint/2`)
  - `context` - Map with restore context (e.g., `:config`)

  ## Returns

  - `{:ok, restored_state}` — The restored plugin state
  - `{:ok, nil}` — State will be rehydrated externally (e.g., by Persist)
  - `{:error, reason}` — Restore failed
  """
  @callback on_restore(pointer :: term(), context :: map()) ::
              {:ok, term()} | {:error, term()}

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

      @doc "Returns whether this plugin is a singleton."
      @spec singleton?() :: boolean()
      def singleton?, do: @validated_opts[:singleton] || false
    end
  end

  defp generate_requirement_accessors do
    quote location: :keep do
      @doc "Returns the requirements for this plugin."
      @spec requires() :: [tuple()]
      def requires, do: @validated_opts[:requires] || []

      @doc "Returns the signal routes for this plugin."
      @spec signal_routes() :: [tuple()]
      def signal_routes, do: @validated_opts[:signal_routes] || []

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
      signal routes, and schedules.
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
          signal_routes: signal_routes(),
          schedules: schedules(),
          signal_patterns: signal_patterns(),
          singleton: singleton?()
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
      @spec signal_routes(map()) :: [tuple()]
      @impl Jido.Plugin
      def signal_routes(_config), do: []

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

      @doc false
      @spec on_checkpoint(term(), map()) ::
              {:externalize, atom(), term()} | :keep | :drop
      @impl Jido.Plugin
      def on_checkpoint(_plugin_state, _context), do: :keep

      @doc false
      @spec on_restore(term(), map()) :: {:ok, term()} | {:error, term()}
      @impl Jido.Plugin
      def on_restore(_pointer, _context), do: {:ok, nil}
    end
  end

  @doc false
  defp generate_defoverridable do
    quote location: :keep do
      defoverridable [
        {:mount, 2},
        {:signal_routes, 0},
        {:signal_routes, 1},
        {:handle_signal, 2},
        {:transform_result, 3},
        {:child_spec, 1},
        {:subscriptions, 2},
        {:on_checkpoint, 2},
        {:on_restore, 2},
        {:name, 0},
        {:state_key, 0},
        {:actions, 0},
        {:description, 0},
        {:category, 0},
        {:vsn, 0},
        {:otp_app, 0},
        {:schema, 0},
        {:config_schema, 0},
        {:signal_patterns, 0},
        {:tags, 0},
        {:capabilities, 0},
        {:requires, 0},
        {:schedules, 0},
        {:singleton?, 0}
      ]
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
