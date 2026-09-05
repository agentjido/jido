defmodule Jido.Agent do
  @moduledoc """
  The canonical immutable Agent value.

  One Agent value has two valid forms. A definition has no identity or state.
  An instance has a non-empty identity and complete portable state. Use
  `new/1` to create a definition and `instantiate/2` to create an instance.
  `cmd/3` applies one Signal to an instance and returns a new Agent plus
  Directives. It does not start or own a process or commit live state.

  The selected Action or Flow can perform synchronous external work. A failed
  command returns no candidate but does not undo completed I/O. Applications
  own external idempotency and recovery. Preparation and state assembly are
  deterministic for fixed inputs and executable results; changing external
  responses can change those results. Use fixed or recorded responses when
  reproducible evaluation is required.

  Agent Plugins can prepare command input before routing. A Plugin cannot
  change domain output. A stateful Plugin can reduce its own declared state
  field after executable work. The Agent validates one complete state proposal.

  Default Signal routing accepts an executable target or `{executable, defaults}`.
  The defaults map is combined with the Signal data using
  `Map.merge(defaults, signal.data)`. Signal values take precedence. The merge
  is shallow: a supplied nested map replaces the corresponding default map.
  An empty Signal data map uses all defaults; non-map data returns a validation
  error. The executable validates the combined input before execution. Invalid
  supplied values do not fall back to defaults. The Signal in execution context
  keeps its original data.

      routes: [{"counter.add", {MyApp.Add, %{amount: 1}}}]

  With this route, `%{}` uses amount 1 and `%{amount: 7}` uses amount 7.
  Route maps are caller-overridable defaults. This changes the earlier behavior,
  which replaced the complete input with the route map. Applications that need
  fixed behavior must enforce it in the Action or construct the input explicitly
  in `handle_signal/2`.

  Routing failures during command preparation return `Jido.Error.RoutingError`
  through both `cmd/3` and `Jido.AgentServer.call/3`. Missing routes, invalid
  Signal types, and multiple matching targets use this public type. Errors from
  the Signal Router retain their message, details, and retry hints; the original
  error is available in `details.cause`. The target is the original error target
  or, when absent, the Signal type. Multiple matches include `details.count` and
  `details.targets`.

  ## Spark authoring

  An Agent module can use keyword configuration or Spark blocks:

      defmodule MyApp.Counter do
        use Jido.Agent, name: "counter"

        agent do
          schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
        end

        routes do
          signal_source "/counter"

          route "counter.add", MyApp.Add do
            defaults %{amount: 1}
            define :add, args: [{:optional, :amount}]
          end
        end
      end

  A nested `define` generates `add_signal`, `add_signal!`, and a live `add`
  helper. For example, `Counter.add_signal(2)` returns `{:ok, signal}`, and
  `Counter.add(server, 2, timeout: 5000)` calls `Jido.AgentServer.call/3`.
  Omitted optional arguments remain absent so route defaults apply normally.
  Extra payload fields use `input: %{...}`; Signal envelope options use
  `signal: [...]`. Only live helpers accept `context` and `timeout` options.
  Helpers package input; Plugins and executables validate it during execution.

  Exposed routes must be exact and have no match predicate. Routes without
  `define` keep normal wildcard and predicate support and generate no helpers.
  A field cannot appear in both keyword and block configuration.

  `Jido.Agent.Builder` and `Jido.Agent.Codec` provide runtime and JSON authoring
  forms through the same construction validator. Use `new/2` for an Agent
  module and instance options. These forms preserve the definition and instance
  boundaries above.
  """

  alias Jido.Agent.{State, Turn}
  alias Jido.Agent.Command.Runner
  alias Jido.Agent.Validation
  alias Jido.Error
  alias Jido.Signal
  alias Jido.Signal.Router

  @checkpoint_version 1

  @schema Zoi.struct(
            __MODULE__,
            %{
              id:
                Zoi.string(description: "Unique Agent instance identifier")
                |> Zoi.nullable()
                |> Zoi.optional(),
              module: Zoi.atom(description: "Agent behavior module"),
              name: Zoi.string(description: "Agent name"),
              description:
                Zoi.string(description: "Agent description")
                |> Zoi.nullable()
                |> Zoi.optional(),
              schema: Zoi.any(description: "Static Zoi schema for Agent-owned state"),
              plugins:
                Zoi.list(Zoi.any(), description: "Canonical ordered Plugin declarations")
                |> Zoi.default([]),
              state:
                Zoi.map(description: "Current complete Agent instance state")
                |> Zoi.nullable()
                |> Zoi.optional(),
              routes:
                Zoi.list(Zoi.any(), description: "Canonical Signal Router routes")
                |> Zoi.default([]),
              metadata: Zoi.map(description: "Portable Agent metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @type handle_result :: {:ok, Turn.t()} | {:error, term()}

  @callback handle_signal(signal :: Signal.t(), agent :: t()) :: handle_result()
  @callback checkpoint(agent :: t(), context :: map()) :: {:ok, map()} | {:error, term()}
  @callback restore(checkpoint :: map(), context :: map()) :: {:ok, t()} | {:error, term()}

  @optional_callbacks checkpoint: 2, restore: 2

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Defines one Agent module with a reusable definition and default Signal behavior."
  defmacro __using__(opts) do
    quote location: :keep do
      use Jido.Agent.DSL
      use Jido.Action.Inline
      @before_compile Jido.Agent.DSL.Compiler
      @behaviour Jido.Agent

      @jido_agent_options unquote(opts)

      @doc "Returns the neutral canonical Agent definition."
      @spec agent() :: Jido.Agent.t()
      def agent do
        case Jido.Agent.__definition_from_module__(__MODULE__, __agent_config__()) do
          {:ok, agent} -> agent
          {:error, error} -> raise error
        end
      end

      @doc "Returns the Agent name."
      @spec name() :: String.t()
      def name, do: Map.fetch!(__agent_config__(), :name)

      @doc "Returns the Agent description."
      @spec description() :: String.t() | nil
      def description, do: Map.get(__agent_config__(), :description)

      @doc "Returns the authored Agent state schema."
      @spec domain_schema() :: Zoi.schema()
      def domain_schema, do: Map.get(__agent_config__(), :schema, Zoi.object(%{}))

      @doc "Returns the authored Agent state schema."
      @spec schema() :: Zoi.schema()
      def schema, do: domain_schema()

      @doc "Returns the complete state schema, including Plugin-owned state."
      @spec complete_schema() :: Zoi.schema()
      def complete_schema, do: Jido.Agent.complete_schema!(agent())

      @doc "Returns the canonical Agent routes."
      @spec routes() :: list()
      def routes, do: agent().routes

      @doc "Returns the Action target compiled for one inline route."
      @spec route_action(String.t()) :: module()
      def route_action(path) do
        Jido.Action.Inline.target!(__MODULE__, host: Jido.Agent, route: path, role: :action)
      end

      @doc "Returns the canonical ordered Agent Plugin declarations."
      @spec plugins() :: list()
      def plugins, do: agent().plugins

      @doc "Returns portable Agent metadata."
      @spec metadata() :: map()
      def metadata, do: agent().metadata

      @doc "Creates one Agent instance from this module definition."
      @spec new(map() | keyword()) :: {:ok, Jido.Agent.t()} | {:error, Exception.t()}
      def new(overrides \\ []) do
        Jido.Agent.__new_from_module__(__MODULE__, __agent_config__(), overrides)
      end

      @doc "Creates one Agent instance or raises its validation error."
      @spec new!(map() | keyword()) :: Jido.Agent.t() | no_return()
      def new!(overrides \\ []) do
        case new(overrides) do
          {:ok, agent} -> agent
          {:error, error} -> raise error
        end
      end

      @doc "Applies one Signal to an Agent value without starting a Server."
      @spec cmd(Jido.Agent.t(), Jido.Signal.t(), keyword()) ::
              {:ok, Jido.Agent.t(), [struct()]} | {:error, term()}
      def cmd(agent, signal, opts \\ []), do: Jido.Agent.cmd(agent, signal, opts)

      @impl Jido.Agent
      def handle_signal(signal, context), do: Jido.Agent.handle_signal(signal, context)

      @impl Jido.Agent
      def checkpoint(agent, context), do: Jido.Agent.default_checkpoint(agent, context)

      @impl Jido.Agent
      def restore(checkpoint, context),
        do: Jido.Agent.default_restore(__MODULE__, checkpoint, context)

      defoverridable handle_signal: 2, checkpoint: 2, restore: 2
    end
  end

  @doc "Returns the Zoi schema for the canonical Agent value."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates one validated neutral Agent definition."
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs), do: Validation.new(attrs)

  @doc "Creates an Agent instance from a module and instance options."
  @spec new(module(), map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(module, opts) when is_atom(module) do
    with {:module, ^module} <- Code.ensure_loaded(module) do
      if function_exported?(module, :__agent_config__, 0),
        do: __new_from_module__(module, module.__agent_config__(), opts),
        else: Jido.Agent.Authoring.error("Expected an Agent module")
    else
      _ -> Jido.Agent.Authoring.error("Agent module could not be loaded")
    end
  end

  def new(_module, _opts), do: Jido.Agent.Authoring.error("Expected an Agent module")

  @doc "Creates an Agent instance from a module or raises its error."
  @spec new!(module(), map() | keyword()) :: t()
  def new!(module, opts) do
    case new(module, opts) do
      {:ok, agent} -> agent
      {:error, error} -> raise error
    end
  end

  @doc "Creates one neutral Agent definition or raises its validation error."
  @spec new!(map() | keyword() | t()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, agent} -> agent
      {:error, error} -> raise error
    end
  end

  @doc "Creates one Agent instance from a neutral definition."
  @spec instantiate(t(), map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def instantiate(%__MODULE__{} = definition, overrides \\ []) do
    Validation.instantiate(definition, overrides)
  end

  @doc "Creates one Agent instance or raises its validation error."
  @spec instantiate!(t(), map() | keyword()) :: t() | no_return()
  def instantiate!(%__MODULE__{} = definition, overrides \\ []) do
    case instantiate(definition, overrides) do
      {:ok, agent} -> agent
      {:error, error} -> raise error
    end
  end

  @doc "Validates one Agent value."
  @spec validate(t()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(value), do: Validation.validate(value)

  @doc "Validates one neutral Agent definition."
  @spec validate_definition(t()) :: {:ok, t()} | {:error, Exception.t()}
  def validate_definition(value), do: Validation.validate_definition(value)

  @doc "Validates one Agent instance."
  @spec validate_instance(t()) :: {:ok, t()} | {:error, Exception.t()}
  def validate_instance(value), do: Validation.validate_instance(value)

  @doc "Returns true when the value is a neutral Agent definition."
  @spec definition?(term()) :: boolean()
  def definition?(%__MODULE__{id: nil, state: nil}), do: true
  def definition?(_value), do: false

  @doc "Returns true when the value has complete Agent instance data."
  @spec instance?(term()) :: boolean()
  def instance?(%__MODULE__{id: id, state: state})
      when is_binary(id) and byte_size(id) > 0 and is_map(state) and not is_struct(state),
      do: true

  def instance?(_value), do: false

  @doc "Returns the neutral canonical definition for an Agent value."
  @spec definition(t()) :: t()
  def definition(%__MODULE__{} = agent), do: %{agent | id: nil, state: nil}

  @doc "Returns the complete state schema, including Plugin-owned state."
  @spec complete_schema(t()) :: {:ok, Zoi.schema()} | {:error, Exception.t()}
  def complete_schema(%__MODULE__{} = agent) do
    Jido.Plugin.compose_schema(agent.schema, agent.plugins)
  end

  @doc "Returns the complete state schema or raises its validation error."
  @spec complete_schema!(t()) :: Zoi.schema() | no_return()
  def complete_schema!(%__MODULE__{} = agent) do
    case complete_schema(agent) do
      {:ok, schema} -> schema
      {:error, error} -> raise error
    end
  end

  @doc "Returns the complete portable Agent value as a map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = agent) do
    %{
      id: agent.id,
      module: agent.module,
      name: agent.name,
      description: agent.description,
      schema: agent.schema,
      plugins: agent.plugins,
      state: agent.state,
      routes: Enum.map(agent.routes, &route_to_map/1),
      metadata: agent.metadata
    }
  end

  @doc "Builds a domain-only checkpoint through the Agent module callback."
  @spec checkpoint(t(), map()) :: {:ok, map()} | {:error, term()}
  def checkpoint(%__MODULE__{} = agent, context \\ %{}) when is_map(context) do
    with {:ok, agent} <- validate_instance(agent),
         {:ok, checkpoint} <-
           invoke_persistence_callback(:checkpoint, fn ->
             if agent.module != __MODULE__ and function_exported?(agent.module, :checkpoint, 2),
               do: agent.module.checkpoint(agent, context),
               else: default_checkpoint(agent, context)
           end),
         :ok <- validate_checkpoint_output(checkpoint) do
      {:ok, checkpoint}
    end
  end

  @doc "Restores an Agent through its module callback."
  @spec restore(module(), map(), map()) :: {:ok, t()} | {:error, term()}
  def restore(module, checkpoint, context \\ %{})
      when is_atom(module) and is_map(checkpoint) and is_map(context) do
    with {:ok, agent} <-
           invoke_persistence_callback(:restore, fn ->
             if module != __MODULE__ and function_exported?(module, :restore, 2),
               do: module.restore(checkpoint, context),
               else: default_restore(module, checkpoint, context)
           end),
         {:ok, agent} <- validate_instance(agent),
         :ok <- validate_restored_module(agent, module) do
      {:ok, agent}
    end
  end

  @doc false
  def default_checkpoint(%__MODULE__{} = agent, _context) do
    {:ok,
     %{
       version: @checkpoint_version,
       kind: :agent,
       agent_module: agent.module,
       id: agent.id,
       definition: definition(agent),
       state: agent.state
     }}
  end

  @doc false
  def default_restore(module, checkpoint, _context) when is_atom(module) and is_map(checkpoint) do
    with :ok <- validate_checkpoint(checkpoint, module),
         {:ok, definition} <- restore_definition(module, checkpoint),
         {:ok, agent} <-
           instantiate(definition, id: checkpoint.id, state: Map.fetch!(checkpoint, :state)) do
      {:ok, agent}
    end
  end

  @doc false
  @spec __definition_from_module__(module(), map() | keyword()) ::
          {:ok, t()} | {:error, Exception.t()}
  def __definition_from_module__(module, definition) when is_atom(module) do
    Validation.definition_from_module(module, definition)
  end

  @doc false
  @spec __new_from_module__(module(), map() | keyword(), map() | keyword()) ::
          {:ok, t()} | {:error, Exception.t()}
  def __new_from_module__(module, definition, overrides) when is_atom(module) do
    Validation.new_from_module(module, definition, overrides)
  end

  @doc false
  @spec transition(t(), term()) :: {:ok, t()} | {:error, Exception.t()}
  def transition(%__MODULE__{} = agent, next_state) do
    with {:ok, agent} <- validate_instance(agent),
         {:ok, schema} <- complete_schema(agent),
         {:ok, state} <- State.validate(next_state, schema) do
      {:ok, %{agent | state: state}}
    end
  end

  @doc "Merges domain attributes and validates the complete next Agent state."
  @spec set(t(), map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def set(%__MODULE__{} = agent, attrs) do
    with {:ok, attrs} <- normalize_domain_attrs(attrs),
         :ok <- validate_domain_attrs(agent, attrs) do
      transition(agent, State.merge(agent.state, attrs))
    end
  end

  @doc "Applies one Signal to an Agent value without starting a Server."
  @spec cmd(t(), Signal.t(), keyword()) ::
          {:ok, t(), [struct()]} | {:error, term()}
  def cmd(%__MODULE__{} = agent, %Signal{} = signal, opts \\ []) when is_list(opts),
    do: Runner.run(agent, signal, opts)

  @doc """
  Routes one Signal to exactly one executable turn.

  A plain target receives Signal data. A `{target, defaults}` route shallowly
  merges the defaults with Signal data, with Signal values taking precedence.
  Both forms require map data. A custom callback can construct its own Turn
  input instead of using this default routing behavior.

  Route selection failures use `Jido.Error.RoutingError`. When `cmd/3` or the
  Agent Server invokes a custom callback, a returned Signal routing error is
  also normalized to this type.
  """
  def handle_signal(%Signal{} = signal, %__MODULE__{} = agent),
    do: Runner.prepare_default_turn(signal, agent)

  defp normalize_domain_attrs(attrs) when is_map(attrs) and not is_struct(attrs),
    do: {:ok, attrs}

  defp normalize_domain_attrs(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      {:ok, Map.new(attrs)}
    else
      invalid("Agent.set/2 attributes must be a map or keyword list", %{attrs: attrs})
    end
  end

  defp normalize_domain_attrs(attrs) do
    invalid("Agent.set/2 attributes must be a map or keyword list", %{attrs: attrs})
  end

  defp validate_domain_attrs(agent, attrs) do
    case agent.schema do
      %Zoi.Types.Map{fields: fields} ->
        invalid_keys = Map.keys(attrs) -- Keyword.keys(fields)

        if invalid_keys == [] do
          :ok
        else
          {:error,
           Error.validation_error("Agent.set/2 accepts only domain state keys",
             details: %{keys: invalid_keys}
           )}
        end

      _schema ->
        {:error, Error.validation_error("Agent domain schema must be a Zoi object")}
    end
  end

  defp route_to_map(%Router.Route{} = route) do
    %{path: route.path, target: route.target, priority: route.priority, match: route.match}
  end

  defp invoke_persistence_callback(callback, fun) do
    case fun.() do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
      value -> {:error, {callback, :invalid_return, value}}
    end
  rescue
    error -> {:error, {callback, :raised, error}}
  catch
    kind, reason -> {:error, {callback, kind, reason}}
  end

  defp validate_checkpoint(checkpoint, module) do
    cond do
      Map.get(checkpoint, :version) != @checkpoint_version ->
        invalid("Agent checkpoint version is invalid", %{version: Map.get(checkpoint, :version)})

      Map.get(checkpoint, :kind) != :agent ->
        invalid("Agent checkpoint kind is invalid", %{kind: Map.get(checkpoint, :kind)})

      Map.get(checkpoint, :agent_module) != module ->
        invalid("Agent checkpoint module does not match", %{
          expected: module,
          actual: Map.get(checkpoint, :agent_module)
        })

      not is_binary(Map.get(checkpoint, :id)) or Map.get(checkpoint, :id) == "" ->
        invalid("Agent checkpoint id is invalid", %{id: Map.get(checkpoint, :id)})

      not is_map(Map.get(checkpoint, :state)) ->
        invalid("Agent checkpoint state must be a map", %{state: Map.get(checkpoint, :state)})

      true ->
        :ok
    end
  end

  defp validate_checkpoint_output(checkpoint)
       when is_map(checkpoint) and not is_struct(checkpoint),
       do: :ok

  defp validate_checkpoint_output(checkpoint) do
    invalid("Agent checkpoint callback must return a map", %{checkpoint: checkpoint})
  end

  defp validate_restored_module(%__MODULE__{module: module}, module), do: :ok

  defp validate_restored_module(%__MODULE__{} = agent, module) do
    invalid("Restored Agent module does not match", %{
      expected: module,
      actual: agent.module
    })
  end

  defp restore_definition(__MODULE__, checkpoint) do
    case Map.get(checkpoint, :definition) do
      %__MODULE__{} = definition ->
        validate_definition(definition)

      %{} = definition ->
        definition
        |> Map.take([:module, :name, :description, :schema, :plugins, :routes, :metadata])
        |> new()

      value ->
        invalid("Agent checkpoint definition is invalid", %{definition: value})
    end
  end

  defp restore_definition(module, _checkpoint) do
    case module.agent() do
      %__MODULE__{} = definition -> validate_definition(definition)
      value -> invalid("Agent definition callback returned an invalid value", %{value: value})
    end
  end

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end
