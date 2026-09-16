defmodule Jido.Agent do
  @moduledoc """
  The canonical immutable Agent value.

  Jido separates declaration from instantiation. A definition declares the
  data schema, routes, Plugins, and metadata, and has no identity or state. An
  instance has a non-empty identity and complete portable state. Use `new/1`
  to create a definition and `instantiate/2` to create an instance.
  `cmd/3` applies one Signal to an instance and returns a new Agent plus
  Directives. It does not start or own a process or commit live state.

  `state` is the Agent's only persistent state map. It contains domain fields
  and one top-level owned field for each stateful Plugin. Jido does not keep a
  second Plugin state map. `schema` describes the domain fields, while
  `complete_schema/1` composes the domain schema with the Plugin-owned fields.

  The selected Action or Flow can perform synchronous external work. A failed
  command returns no candidate but does not undo completed I/O. Applications
  own external idempotency and recovery. Preparation and state assembly are
  deterministic for fixed inputs and executable results; changing external
  responses can change those results. Use fixed or recorded responses when
  reproducible evaluation is required.

  Before route selection, each Agent Plugin can inspect the source Signal,
  Agent identity, and its owned state. It can reject the command or return one
  portable input under its package key. It cannot change the source Signal,
  caller context, route, or Agent state. After executable work, a stateful
  Plugin can reduce only its declared state field. The Agent validates one
  complete state proposal.

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
  through both `cmd/3` and `Jido.AgentServer.call/3`. Missing routes and invalid
  Signal types use this public type. When several targets match, Jido uses the
  first target in Router order. Errors from the Signal Router retain their
  message, details, and retry hints; the original error is available in
  `details.cause`. The target is the original error target or, when absent, the
  Signal type.

  ## Declarative authoring

  An Agent module can use keyword configuration or declarative blocks:

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

  `Jido.Agent.Builder` and `Jido.Agent.Codec` provide programmatic and JSON
  declaration forms through the same validator. Use `instantiate/2` for an
  Agent module and instance options. These forms preserve the definition and instance
  boundaries above.

  A generated Agent module owns a positive definition `vsn` and defaults to
  `1`. Direct and behavior-only definitions can use `nil` for compatibility.
  The default generated-module checkpoint stores the module, `vsn`, identity,
  and complete combined state in format version 2. Restore rejects a module or
  `vsn` mismatch before it constructs an Agent. Custom callbacks keep an opaque
  map payload inside a core-owned revision envelope. Checkpoints use only this
  V3 format.

  Agent state must contain portable terms. PIDs, ports, references, functions,
  improper lists, and non-byte-aligned bitstrings are rejected with a bounded
  path. This state rule does not restrict static direct-definition data while
  it stays in memory. A default embedded-definition checkpoint must still be
  fully portable.
  """

  alias Jido.Agent.{Checkpoint, State, Turn}
  alias Jido.Agent.Runner
  alias Jido.Agent.Validation
  alias Jido.Error
  alias Jido.Signal

  @schema Zoi.struct(
            __MODULE__,
            %{
              id:
                Zoi.string(description: "Unique Agent instance identifier")
                |> Zoi.nullable()
                |> Zoi.optional(),
              module: Zoi.atom(description: "Agent behavior module"),
              vsn:
                Zoi.integer(description: "Agent definition version")
                |> Zoi.min(1)
                |> Zoi.nullable()
                |> Zoi.optional(),
              name: Zoi.string(description: "Agent name"),
              description:
                Zoi.string(description: "Agent description")
                |> Zoi.nullable()
                |> Zoi.optional(),
              schema: Zoi.any(description: "Static data schema for Agent-owned state"),
              plugins:
                Zoi.list(Zoi.any(), description: "Canonical ordered Plugin declarations")
                |> Zoi.default([]),
              state:
                Zoi.map(description: "Sole combined domain and Plugin-owned Agent state")
                |> Zoi.nullable()
                |> Zoi.optional(),
              routes:
                Zoi.list(Zoi.any(), description: "Canonical Signal Router routes")
                |> Zoi.default([]),
              metadata: Zoi.map(description: "Agent definition metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type definition :: %__MODULE__{id: nil, state: nil}
  @type instance :: %__MODULE__{id: String.t(), state: map()}
  @type t :: definition() | instance()
  @type handle_result :: {:ok, Turn.t()} | {:error, term()}

  @callback handle_signal(signal :: Signal.t(), agent :: instance()) :: handle_result()
  @callback checkpoint(agent :: instance(), context :: map()) :: {:ok, map()} | {:error, term()}
  @callback restore(checkpoint :: map(), context :: map()) ::
              {:ok, instance()} | {:error, term()}

  @optional_callbacks handle_signal: 2, checkpoint: 2, restore: 2

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Declares one Agent module with a reusable definition and default Signal behavior."
  defmacro __using__(opts) do
    quote location: :keep do
      use Jido.Agent.Definition,
        dsl: Jido.Agent.DSL,
        agent_options: unquote(opts),
        constructors?: true,
        combined_extensions?: false
    end
  end

  @doc "Creates one validated neutral Agent definition."
  @spec new(map() | keyword() | definition()) ::
          {:ok, definition()} | {:error, Exception.t()}
  def new(attrs), do: Validation.new(attrs)

  @doc "Creates one neutral Agent definition or raises its validation error."
  @spec new!(map() | keyword() | definition()) :: definition() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, agent} -> agent
      {:error, error} -> raise error
    end
  end

  @doc "Creates one Agent instance from a neutral definition or Agent module."
  @spec instantiate(definition() | module(), map() | keyword()) ::
          {:ok, instance()} | {:error, Exception.t()}
  def instantiate(source, overrides \\ [])

  def instantiate(module, overrides) when is_atom(module) do
    with {:module, ^module} <- Code.ensure_loaded(module) do
      if function_exported?(module, :__agent_config__, 0),
        do: __new_from_module__(module, module.__agent_config__(), overrides),
        else: Jido.Agent.Authoring.error("Expected an Agent module")
    else
      _ -> Jido.Agent.Authoring.error("Agent module could not be loaded")
    end
  end

  def instantiate(%__MODULE__{} = definition, overrides) do
    Validation.instantiate(definition, overrides)
  end

  def instantiate(_source, _overrides),
    do: Jido.Agent.Authoring.error("Expected a neutral Agent definition or Agent module")

  @doc "Creates one Agent instance or raises its validation error."
  @spec instantiate!(definition() | module(), map() | keyword()) :: instance() | no_return()
  def instantiate!(source, overrides \\ []) do
    case instantiate(source, overrides) do
      {:ok, agent} -> agent
      {:error, error} -> raise error
    end
  end

  @doc "Validates one Agent value."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(value), do: Validation.validate(value)

  @doc "Validates one neutral Agent definition."
  @spec validate_definition(term()) :: {:ok, definition()} | {:error, Exception.t()}
  def validate_definition(value), do: Validation.validate_definition(value)

  @doc "Validates one Agent instance."
  @spec validate_instance(term()) :: {:ok, instance()} | {:error, Exception.t()}
  def validate_instance(value), do: Validation.validate_instance(value)

  @doc "Returns true when the value is a neutral Agent definition."
  @spec definition?(term()) :: boolean()
  def definition?(value), do: match?({:ok, %__MODULE__{}}, validate_definition(value))

  @doc "Returns true when the value has complete Agent instance data."
  @spec instance?(term()) :: boolean()
  def instance?(value), do: match?({:ok, %__MODULE__{}}, validate_instance(value))

  @doc "Returns the neutral canonical definition for an Agent value."
  @spec definition(t()) :: definition()
  def definition(%__MODULE__{} = agent), do: %{agent | id: nil, state: nil}

  @doc "Returns the complete data schema, including Plugin-owned fields in Agent state."
  @spec complete_schema(t()) :: {:ok, Zoi.schema()} | {:error, Exception.t()}
  def complete_schema(%__MODULE__{} = agent) do
    Jido.Agent.Plugin.compose_schema(agent.schema, agent.plugins)
  end

  @doc "Returns the complete data schema or raises its validation error."
  @spec complete_schema!(t()) :: Zoi.schema() | no_return()
  def complete_schema!(%__MODULE__{} = agent) do
    case complete_schema(agent) do
      {:ok, schema} -> schema
      {:error, error} -> raise error
    end
  end

  @doc "Builds a complete-state checkpoint through the Agent module callback."
  @spec checkpoint(instance(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate checkpoint(agent, context \\ %{}), to: Checkpoint

  @doc "Restores an Agent through its module callback."
  @spec restore(module(), map(), map()) :: {:ok, instance()} | {:error, term()}
  defdelegate restore(module, checkpoint, context \\ %{}), to: Checkpoint

  @doc false
  defdelegate default_checkpoint(agent, context), to: Checkpoint

  @doc false
  defdelegate default_restore(module, checkpoint, context), to: Checkpoint

  @doc false
  @spec __definition_from_module__(module(), map() | keyword()) ::
          {:ok, definition()} | {:error, Exception.t()}
  def __definition_from_module__(module, definition) when is_atom(module) do
    Validation.definition_from_module(module, definition)
  end

  @doc false
  @spec __new_from_module__(module(), map() | keyword(), map() | keyword()) ::
          {:ok, instance()} | {:error, Exception.t()}
  def __new_from_module__(module, definition, overrides) when is_atom(module) do
    Validation.new_from_module(module, definition, overrides)
  end

  @doc false
  @spec transition(instance(), term()) :: {:ok, instance()} | {:error, Exception.t()}
  def transition(%__MODULE__{} = agent, next_state) do
    with {:ok, agent} <- validate_instance(agent) do
      transition_validated(agent, next_state)
    end
  end

  @doc false
  @spec transition_validated(instance(), term()) ::
          {:ok, instance()} | {:error, Exception.t()}
  def transition_validated(%__MODULE__{} = agent, next_state) do
    with {:ok, schema} <- complete_schema(agent),
         {:ok, state} <- State.validate_candidate(next_state, schema) do
      {:ok, %{agent | state: state}}
    end
  end

  @doc "Merges domain attributes and validates the complete next Agent state."
  @spec set(instance(), map() | keyword()) :: {:ok, instance()} | {:error, Exception.t()}
  def set(%__MODULE__{} = agent, attrs) do
    with {:ok, attrs} <- normalize_domain_attrs(attrs),
         :ok <- validate_domain_attrs(agent, attrs) do
      if not is_map(agent.state) or is_struct(agent.state) do
        invalid("Agent.set/2 requires an instance", %{id: agent.id, state: agent.state})
      else
        transition(agent, State.merge(agent.state, attrs))
      end
    end
  end

  @doc """
  Applies one Signal to an Agent value without starting a Server.

  This function runs pure Agent Plugin preparation. It does not run live Agent
  Server Plugin admission, runtime work, replay protection, or outbound Signal
  preparation.
  """
  @spec cmd(instance(), Signal.t(), keyword()) ::
          {:ok, instance(), [struct()]} | {:error, term()}
  def cmd(agent, signal, opts \\ [])

  def cmd(%__MODULE__{} = agent, %Signal{} = signal, opts) when is_list(opts) do
    if Keyword.keyword?(opts),
      do: Runner.run(agent, signal, opts),
      else: invalid("Agent.cmd/3 options must be a keyword list", %{opts: opts})
  end

  def cmd(%__MODULE__{}, %Signal{}, opts),
    do: invalid("Agent.cmd/3 options must be a keyword list", %{opts: opts})

  @doc false
  @spec handle_signal(Signal.t(), instance()) :: handle_result()
  def handle_signal(%Signal{} = signal, %__MODULE__{} = agent),
    do: Runner.prepare_default_turn(signal, agent)

  defp normalize_domain_attrs(attrs) do
    case Jido.Agent.Authoring.to_attrs(attrs) do
      {:ok, attrs} -> {:ok, attrs}
      :error -> invalid("Agent.set/2 attributes must be a map or keyword list", %{attrs: attrs})
    end
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

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end
