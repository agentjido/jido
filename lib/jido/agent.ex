defmodule Jido.Agent do
  @moduledoc """
  The canonical immutable Agent value.

  Jido separates declaration from instantiation. A definition declares the
  data schema, routes, Plugins, and metadata, and has no identity or state. An
  instance has a non-empty identity and complete portable state. Use `new/1`
  to create a definition and `instantiate/2` to create an instance.
  `cmd/3` applies one Signal to an instance and returns a new Agent plus
  Directives. It does not start or own a process or commit live state.

  The selected Action or Flow can perform synchronous external work. A failed
  command returns no candidate but does not undo completed I/O. Applications
  own external idempotency and recovery. Preparation and state assembly are
  deterministic for fixed inputs and executable results; changing external
  responses can change those results. Use fixed or recorded responses when
  reproducible evaluation is required.

  Jido selects the first matching route from the unchanged source Signal before
  Agent Plugins prepare command input. A Plugin cannot replace that selection
  or change domain output. A stateful Plugin can reduce its own declared state
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
  declaration forms through the same validator. Use `new/2` for an Agent module
  and instance options. These forms preserve the definition and instance
  boundaries above.

  A generated Agent module owns a positive definition `vsn` and defaults to
  `1`. Direct and behavior-only definitions can use `nil` for compatibility.
  The default generated-module checkpoint stores the module, `vsn`, identity,
  and complete combined state in format version 2. Restore rejects a module or
  `vsn` mismatch before it constructs an Agent. Custom callbacks keep an opaque
  map payload inside a core-owned revision envelope. Legacy version-1 default
  checkpoints and raw custom callback maps remain readable.

  Agent state must contain portable terms. PIDs, ports, references, functions,
  improper lists, and non-byte-aligned bitstrings are rejected with a bounded
  path. This state rule does not restrict static direct-definition data while
  it stays in memory. A default embedded-definition checkpoint must still be
  fully portable.
  """

  alias Jido.Agent.{State, Turn}
  alias Jido.Agent.Command.Runner
  alias Jido.Agent.Validation
  alias Jido.Error
  alias Jido.PortableTerm
  alias Jido.Signal
  alias Jido.Signal.Router

  @legacy_checkpoint_version 1
  @checkpoint_version 2
  @custom_checkpoint_kind :agent_custom

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
                Zoi.map(description: "Current complete Agent instance state")
                |> Zoi.nullable()
                |> Zoi.optional(),
              routes:
                Zoi.list(Zoi.any(), description: "Canonical Signal Router routes")
                |> Zoi.default([]),
              metadata: Zoi.map(description: "Agent definition metadata") |> Zoi.default(%{})
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

  @doc "Declares one Agent module with a reusable definition and default Signal behavior."
  defmacro __using__(opts) do
    {host, agent_opts} = authoring_host(opts)

    {dsl, constructors?, combined_extensions?} =
      case host do
        :topology -> {Jido.Topology.DSL, false, true}
        :agent -> {Jido.Agent.DSL, true, false}
      end

    dsl_opts =
      if is_list(agent_opts) do
        extensions = Keyword.get(agent_opts, :extensions)

        if is_nil(extensions), do: [], else: [extensions: extensions]
      else
        []
      end

    constructors =
      if constructors? do
        quote location: :keep do
          @doc "Creates one Agent instance from this module definition."
          @spec new(map() | keyword()) :: {:ok, Jido.Agent.t()} | {:error, Exception.t()}
          def new(overrides \\ []) do
            Jido.Agent.new(__MODULE__, overrides)
          end

          @doc "Creates one Agent instance or raises its validation error."
          @spec new!(map() | keyword()) :: Jido.Agent.t() | no_return()
          def new!(overrides \\ []) do
            Jido.Agent.new!(__MODULE__, overrides)
          end
        end
      end

    quote location: :keep do
      use unquote(dsl), unquote(dsl_opts)
      use Jido.Action.Inline
      Module.register_attribute(__MODULE__, :jido_handle_signal_definition_count, persist: false)
      @jido_handle_signal_definition_count 0
      @on_definition {Jido.Agent, :__on_definition__}
      @before_compile Jido.Agent.DSL.Compiler
      @behaviour Jido.Agent

      @jido_agent_options unquote(agent_opts)
      @jido_agent_combined_extensions unquote(combined_extensions?)

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

      @doc "Returns the positive Agent definition version owned by this module."
      @spec vsn() :: pos_integer()
      def vsn, do: Map.fetch!(__agent_config__(), :vsn)

      @doc "Returns the authored Agent data schema."
      @spec domain_schema() :: Zoi.schema()
      def domain_schema, do: Map.get(__agent_config__(), :schema, Zoi.object(%{}))

      @doc "Returns the authored Agent data schema."
      @spec schema() :: Zoi.schema()
      def schema, do: domain_schema()

      @doc "Returns the complete data schema, including Plugin-owned state."
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

      @doc "Returns the Agent definition metadata."
      @spec metadata() :: map()
      def metadata, do: agent().metadata

      unquote(constructors)

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

  @doc false
  def __on_definition__(env, _kind, :handle_signal, args, _guards, _body)
      when length(args) == 2 do
    count = Module.get_attribute(env.module, :jido_handle_signal_definition_count) || 0
    Module.put_attribute(env.module, :jido_handle_signal_definition_count, count + 1)
  end

  def __on_definition__(_env, _kind, _name, _args, _guards, _body), do: :ok

  defp authoring_host({:{}, _metadata, [:__jido_internal_host__, :topology, agent_options]}),
    do: {:topology, agent_options}

  defp authoring_host(agent_options), do: {:agent, agent_options}

  @doc "Returns the data schema for the canonical Agent value."
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

  @doc "Returns the complete data schema, including Plugin-owned state."
  @spec complete_schema(t()) :: {:ok, Zoi.schema()} | {:error, Exception.t()}
  def complete_schema(%__MODULE__{} = agent) do
    Jido.Plugin.compose_schema(agent.schema, agent.plugins)
  end

  @doc "Returns the complete data schema or raises its validation error."
  @spec complete_schema!(t()) :: Zoi.schema() | no_return()
  def complete_schema!(%__MODULE__{} = agent) do
    case complete_schema(agent) do
      {:ok, schema} -> schema
      {:error, error} -> raise error
    end
  end

  @doc "Returns the complete Agent value as a map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = agent) do
    %{
      id: agent.id,
      module: agent.module,
      vsn: agent.vsn,
      name: agent.name,
      description: agent.description,
      schema: agent.schema,
      plugins: agent.plugins,
      state: agent.state,
      routes: Enum.map(agent.routes, &route_to_map/1),
      metadata: agent.metadata
    }
  end

  @doc "Builds a complete-state checkpoint through the Agent module callback."
  @spec checkpoint(t(), map()) :: {:ok, map()} | {:error, term()}
  def checkpoint(%__MODULE__{} = agent, context \\ %{}) when is_map(context) do
    with {:ok, agent} <- validate_instance(agent),
         {:ok, checkpoint} <-
           invoke_persistence_callback(:checkpoint, fn ->
             if agent.module != __MODULE__ and function_exported?(agent.module, :checkpoint, 2),
               do: agent.module.checkpoint(agent, context),
               else: default_checkpoint(agent, context)
           end),
         {:ok, checkpoint} <- prepare_checkpoint_output(agent, checkpoint) do
      {:ok, checkpoint}
    end
  end

  @doc "Restores an Agent through its module callback."
  @spec restore(module(), map(), map()) :: {:ok, t()} | {:error, term()}
  def restore(module, checkpoint, context \\ %{})
      when is_atom(module) and is_map(checkpoint) and is_map(context) do
    with {:ok, callback_checkpoint, saved_vsn} <- prepare_restore_input(module, checkpoint),
         {:ok, agent} <-
           invoke_persistence_callback(:restore, fn ->
             if module != __MODULE__ and Code.ensure_loaded?(module) and
                  function_exported?(module, :restore, 2),
                do: module.restore(callback_checkpoint, context),
                else: default_restore(module, callback_checkpoint, context)
           end),
         {:ok, agent} <- validate_instance(agent),
         :ok <- validate_restored_module(agent, module),
         :ok <- validate_restored_vsn(agent, saved_vsn) do
      {:ok, agent}
    end
  end

  @doc false
  def default_checkpoint(%__MODULE__{} = agent, _context) do
    with {:ok, agent} <- validate_instance(agent),
         {:ok, checkpoint} <- build_default_checkpoint(agent),
         :ok <- validate_portable(checkpoint, :checkpoint) do
      {:ok, checkpoint}
    end
  end

  @doc false
  def default_restore(module, checkpoint, _context) when is_atom(module) and is_map(checkpoint) do
    with :ok <- validate_portable(checkpoint, :checkpoint),
         {:ok, version} <- validate_checkpoint(checkpoint, module),
         {:ok, definition} <- restore_definition(module, checkpoint, version),
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
  Routes one Signal to the first matching executable Turn.

  A plain target receives Signal data. A `{target, defaults}` route shallowly
  merges the defaults with Signal data, with Signal values taking precedence.
  Both forms require map data. A custom callback can construct its own Turn
  input instead of using this default routing behavior.

  The returned Turn contains the unchanged source Signal. Route selection
  failures use `Jido.Error.RoutingError`. When `cmd/3` or the
  Agent Server invokes a custom callback, a returned Signal routing error is
  also normalized to this type.
  """
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

  defp route_to_map(%Router.Route{} = route) do
    %{path: route.path, target: route.target, priority: route.priority, match: route.match}
  end

  defp invoke_persistence_callback(callback, fun) do
    case fun.() do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        {:error, reason}

      value ->
        {:error,
         Error.validation_error("Agent #{callback}/2 returned an invalid result",
           kind: :config,
           details: %{
             code: :agent_invalid_callback_result,
             callback: callback,
             result: value
           }
         )}
    end
  rescue
    error -> persistence_callback_error(callback, :error, error)
  catch
    kind, reason -> persistence_callback_error(callback, kind, reason)
  end

  defp persistence_callback_error(callback, kind, reason) do
    {:error,
     Error.execution_error("Agent #{callback}/2 failed",
       details: %{
         code: :agent_callback_failed,
         callback: callback,
         kind: kind,
         reason: reason
       }
     )}
  end

  defp validate_checkpoint(checkpoint, module) do
    version = Map.get(checkpoint, :version)

    cond do
      version not in [@legacy_checkpoint_version, @checkpoint_version] ->
        invalid("Agent checkpoint version is invalid", %{version: version})

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

      version == @checkpoint_version and
          (not is_integer(Map.get(checkpoint, :vsn)) or Map.get(checkpoint, :vsn) <= 0) ->
        invalid("Agent checkpoint vsn is invalid", %{vsn: Map.get(checkpoint, :vsn)})

      true ->
        {:ok, version}
    end
  end

  defp build_default_checkpoint(%__MODULE__{} = agent) do
    if is_nil(agent.vsn),
      do: build_legacy_checkpoint(agent),
      else: build_versioned_checkpoint(agent)
  end

  defp build_versioned_checkpoint(%__MODULE__{} = agent) do
    case current_generated_definition(agent.module) do
      {:ok, current_definition} ->
        if definition(agent) === current_definition do
          {:ok,
           %{
             version: @checkpoint_version,
             kind: :agent,
             agent_module: agent.module,
             vsn: agent.vsn,
             id: agent.id,
             state: agent.state
           }}
        else
          definition_mismatch("Agent instance definition does not match its generated module", %{
            module: agent.module,
            instance_vsn: agent.vsn,
            module_vsn: current_definition.vsn
          })
        end

      :not_generated ->
        build_legacy_checkpoint(agent)

      {:error, _error} = error ->
        error
    end
  end

  defp build_legacy_checkpoint(%__MODULE__{} = agent) do
    {:ok,
     %{
       version: @legacy_checkpoint_version,
       kind: :agent,
       agent_module: agent.module,
       id: agent.id,
       definition: definition(agent),
       state: agent.state
     }}
  end

  defp prepare_checkpoint_output(agent, checkpoint) do
    with :ok <- validate_checkpoint_output(checkpoint) do
      if default_checkpoint_output?(agent, checkpoint) do
        with :ok <- validate_portable(checkpoint, :checkpoint), do: {:ok, checkpoint}
      else
        with :ok <- validate_current_module_vsn(agent.module, agent.vsn) do
          envelope = %{
            version: @checkpoint_version,
            kind: @custom_checkpoint_kind,
            agent_module: agent.module,
            vsn: agent.vsn,
            payload: checkpoint
          }

          with :ok <- validate_portable(envelope, :checkpoint), do: {:ok, envelope}
        end
      end
    end
  end

  defp default_checkpoint_output?(agent, checkpoint) do
    case build_default_checkpoint(agent) do
      {:ok, expected} -> checkpoint === expected
      {:error, _error} -> false
    end
  end

  defp exact_keys?(map, keys), do: Enum.sort(Map.keys(map)) == Enum.sort(keys)

  defp prepare_restore_input(module, checkpoint) do
    with :ok <- validate_portable(checkpoint, :checkpoint) do
      if Map.get(checkpoint, :kind) == @custom_checkpoint_kind do
        prepare_custom_restore_input(module, checkpoint)
      else
        {:ok, checkpoint, :legacy_or_default}
      end
    end
  end

  defp prepare_custom_restore_input(module, checkpoint) do
    cond do
      not exact_keys?(checkpoint, [
        :version,
        :kind,
        :agent_module,
        :vsn,
        :payload
      ]) ->
        invalid("Custom Agent checkpoint envelope is invalid", %{
          code: :invalid_checkpoint
        })

      Map.get(checkpoint, :version) != @checkpoint_version ->
        invalid("Custom Agent checkpoint version is invalid", %{
          code: :invalid_checkpoint,
          version: Map.get(checkpoint, :version)
        })

      Map.get(checkpoint, :agent_module) != module ->
        definition_mismatch("Custom Agent checkpoint module does not match", %{
          expected: module,
          actual: Map.get(checkpoint, :agent_module)
        })

      not is_map(Map.get(checkpoint, :payload)) or is_struct(Map.get(checkpoint, :payload)) ->
        invalid("Custom Agent checkpoint payload must be a plain map", %{
          code: :invalid_checkpoint
        })

      not valid_vsn?(Map.get(checkpoint, :vsn)) ->
        invalid("Custom Agent checkpoint vsn is invalid", %{
          code: :invalid_checkpoint,
          vsn: Map.get(checkpoint, :vsn)
        })

      true ->
        with :ok <- validate_current_module_vsn(module, Map.get(checkpoint, :vsn)) do
          {:ok, Map.fetch!(checkpoint, :payload), {:custom, Map.get(checkpoint, :vsn)}}
        end
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

  defp validate_restored_vsn(_agent, :legacy_or_default), do: :ok
  defp validate_restored_vsn(%__MODULE__{vsn: vsn}, {:custom, vsn}), do: :ok

  defp validate_restored_vsn(%__MODULE__{} = agent, {:custom, saved_vsn}) do
    definition_mismatch("Restored Agent vsn does not match", %{
      saved_vsn: saved_vsn,
      restored_vsn: agent.vsn
    })
  end

  defp restore_definition(__MODULE__, checkpoint, @legacy_checkpoint_version),
    do: restore_checkpoint_definition(checkpoint)

  defp restore_definition(__MODULE__, _checkpoint, @checkpoint_version) do
    invalid("Version-2 Agent checkpoints require a generated Agent module", %{
      code: :invalid_checkpoint
    })
  end

  defp restore_definition(module, checkpoint, @checkpoint_version) do
    with {:ok, definition} <- require_generated_definition(module),
         :ok <- compare_vsn(definition.vsn, Map.fetch!(checkpoint, :vsn)) do
      {:ok, definition}
    end
  end

  defp restore_definition(module, checkpoint, @legacy_checkpoint_version) do
    if explicit_unversioned_definition?(checkpoint) do
      restore_checkpoint_definition(checkpoint)
    else
      case current_generated_definition(module) do
        {:ok, definition} ->
          saved_vsn = Map.get(checkpoint, :vsn, 1)

          with :ok <- compare_vsn(definition.vsn, saved_vsn), do: {:ok, definition}

        :not_generated ->
          restore_checkpoint_definition(checkpoint)

        {:error, _error} = error ->
          error
      end
    end
  end

  defp explicit_unversioned_definition?(checkpoint) do
    case Map.get(checkpoint, :definition) do
      %{} = definition -> Map.has_key?(definition, :vsn) and is_nil(Map.get(definition, :vsn))
      _other -> false
    end
  end

  defp restore_checkpoint_definition(checkpoint) do
    case Map.get(checkpoint, :definition) do
      %{} = definition ->
        definition
        |> Map.delete(:__struct__)
        |> Map.take([
          :module,
          :vsn,
          :name,
          :description,
          :schema,
          :plugins,
          :routes,
          :metadata
        ])
        |> new()

      value ->
        invalid("Agent checkpoint definition is invalid", %{definition: value})
    end
  end

  defp current_generated_definition(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__agent_config__, 0) and
         function_exported?(module, :agent, 0) do
      case module.agent() do
        %__MODULE__{} = definition -> validate_definition(definition)
        value -> invalid("Agent definition callback returned an invalid value", %{value: value})
      end
    else
      :not_generated
    end
  end

  defp require_generated_definition(module) do
    case current_generated_definition(module) do
      {:ok, definition} ->
        {:ok, definition}

      :not_generated ->
        invalid("Version-2 Agent checkpoints require a generated Agent module", %{
          code: :invalid_checkpoint,
          module: module
        })

      {:error, _error} = error ->
        error
    end
  end

  defp validate_current_module_vsn(module, saved_vsn) do
    case current_generated_definition(module) do
      {:ok, definition} -> compare_vsn(definition.vsn, saved_vsn)
      :not_generated -> :ok
      {:error, _error} = error -> error
    end
  end

  defp compare_vsn(vsn, vsn), do: :ok

  defp compare_vsn(current_vsn, saved_vsn) do
    definition_mismatch("Agent checkpoint vsn does not match", %{
      current_vsn: current_vsn,
      saved_vsn: saved_vsn
    })
  end

  defp valid_vsn?(nil), do: true
  defp valid_vsn?(vsn), do: is_integer(vsn) and vsn > 0

  defp validate_portable(value, root) do
    case PortableTerm.validate(value, root) do
      :ok ->
        :ok

      {:error, path} ->
        {:error,
         Error.validation_error("Agent checkpoint contains a non-portable term",
           kind: :config,
           details: %{code: :non_portable_term, path: path}
         )}
    end
  end

  defp definition_mismatch(message, details) do
    invalid(message, Map.put(details, :code, :definition_mismatch))
  end

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end
