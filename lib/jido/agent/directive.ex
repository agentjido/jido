defmodule Jido.Agent.Directive do
  @moduledoc """
  Changes and runtime work returned by an Agent executable turn.

  The terminal Action or Flow output is complete next Agent state. Plugin-owned
  fields must remain unchanged until their owning Plugin reduces the batch.
  Topology and Plugin Directives edit definition data on that same candidate.
  Plugin-owned Directives can change their owner's state during reduction and
  request runtime work after commit. `Jido.AgentServer` commits the candidate
  before it dispatches runtime work. A dispatch failure does not undo that
  commit. A later Agent state change must enter through a Signal.

  Return `{:ok, state, directives}` from an Action.
  Flow preserves the batch from all successful executed components. A failed
  Flow returns no executable batch. Core validates every Directive and the
  complete state before commit. The third element is an optional proper list
  for both direct Actions and Flow composition.

  Directives request runtime operations or work that must happen after commit.
  An Action or Flow can also perform synchronous I/O before returning its
  complete state. That I/O is outside the Agent state transaction and is not
  undone if the Turn fails.

  A custom Directive uses this module as a behavior. `use Jido.Agent.Directive`
  supplies a default `validate/1` callback. The default applies `schema/0` when
  the Directive module defines it. A Directive can override `validate/1` when
  it needs another validation rule.
  """

  alias __MODULE__.Emit
  alias Jido.AgentServer.Directive, as: Runtime

  alias Jido.AgentServer.Directive.{
    AgentSend,
    AgentStart,
    AgentStop,
    ErrorReport,
    OwnerSend,
    ProcessStart,
    ServerStop
  }

  alias Jido.Signal
  alias __MODULE__.{PluginAdd, PluginConfigure, PluginRemove}
  alias Jido.Signal.Context, as: SignalContext

  @callback validate(directive :: struct()) :: {:ok, struct()} | {:error, term()}

  @doc "Defines a self-validating custom Agent Directive."
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Jido.Agent.Directive

      @impl Jido.Agent.Directive
      # `use` can precede `defstruct`; do not expand the struct here.
      def validate(%{__struct__: __MODULE__} = directive) do
        if function_exported?(__MODULE__, :schema, 0) do
          Zoi.parse(apply(__MODULE__, :schema, []), Map.from_struct(directive))
        else
          {:ok, directive}
        end
      end

      def validate(value) do
        {:error,
         Jido.Error.validation_error("Expected a #{inspect(__MODULE__)} Directive",
           details: %{directive: value}
         )}
      end

      defoverridable validate: 1
    end
  end

  @type t :: struct()

  @built_ins [
    Emit,
    AgentSend,
    AgentStart,
    AgentStop,
    ErrorReport,
    OwnerSend,
    ProcessStart,
    ServerStop
  ]

  @mutation_modules Jido.Agent.Mutation.modules()

  @doc "Returns true when the value is a built-in Agent Directive."
  @spec built_in?(term()) :: boolean()
  def built_in?(%{__struct__: module}), do: module in @built_ins or module in @mutation_modules
  def built_in?(_value), do: false

  @doc false
  @spec built_in_module?(module()) :: boolean()
  def built_in_module?(module) when is_atom(module),
    do: module in @built_ins or module in @mutation_modules

  @doc false
  @spec validator?(module()) :: boolean()
  def validator?(module) when is_atom(module),
    do: built_in_module?(module) or function_exported?(module, :validate, 1)

  @doc "Validates one built-in or custom Agent Directive."
  @spec validate(struct()) :: {:ok, struct()} | {:error, term()}
  def validate(%{__struct__: module, signal: %Signal{} = signal} = directive)
      when module in [Emit, OwnerSend, AgentSend] do
    with {:ok, signal} <- Zoi.parse(Signal.schema(), signal),
         {:ok, extensions} <- SignalContext.normalize(signal.extensions) do
      directive
      |> Map.from_struct()
      |> Map.put(:signal, %{signal | extensions: extensions})
      |> then(&Zoi.parse(module.schema(), &1))
    end
  end

  def validate(%{__struct__: module} = directive)
      when module in [Emit, OwnerSend, AgentSend] do
    {:error,
     Jido.Error.validation_error("Agent Signal Directive requires a Jido.Signal",
       details: %{directive: directive}
     )}
  end

  def validate(%AgentStart{} = directive) do
    with {:ok, directive} <- Zoi.parse(AgentStart.schema(), Map.from_struct(directive)),
         :ok <- Runtime.validate_agent_target(directive.agent) do
      {:ok, directive}
    end
  end

  def validate(%{__struct__: module} = directive) when module in @mutation_modules,
    do: Jido.Agent.Mutation.validate(directive)

  def validate(%{__struct__: module} = directive) when module in @built_ins do
    Zoi.parse(module.schema(), Map.from_struct(directive))
  end

  def validate(%{__struct__: module} = directive) do
    try do
      case module.validate(directive) do
        {:ok, %{__struct__: ^module} = validated} ->
          {:ok, validated}

        {:ok, %{__struct__: actual}} ->
          {:error,
           Jido.Error.validation_error("Agent Directive validation changed its type",
             details: %{expected: module, actual: actual}
           )}

        {:error, _reason} = error ->
          error

        result ->
          {:error,
           Jido.Error.validation_error("Agent Directive validate/1 returned an invalid result",
             details: %{directive: module, result: result}
           )}
      end
    rescue
      error ->
        {:error,
         Jido.Error.execution_error("Agent Directive validation failed",
           details: %{directive: module, error: error}
         )}
    catch
      kind, reason ->
        {:error,
         Jido.Error.execution_error("Agent Directive validation failed",
           details: %{directive: module, kind: kind, reason: reason}
         )}
    end
  end

  def validate(value) do
    {:error,
     Jido.Error.validation_error("Unknown Agent Directive",
       details: %{directive: value}
     )}
  end

  @doc """
  Creates an emission request. It does not dispatch a Signal.

  The type/data form uses the owning Agent's explicit Signal source when the
  command runs. The full-Signal form preserves its envelope.
  """
  @spec emit(Signal.t() | String.t(), term()) :: Emit.t() | map() | {:error, term()}
  def emit(signal_or_type, dispatch_or_data \\ nil)

  def emit(type, data) when is_binary(type) do
    with :ok <- Jido.Agent.Data.exact(type),
         :ok <- Jido.Agent.Data.plain_map(data),
         do: %{kind: :emit, type: type, data: data}
  end

  def emit(%Signal{} = signal, dispatch), do: %Emit{signal: signal, dispatch: dispatch}

  @doc "Replaces the complete topology data."
  def topology_set(topology), do: %__MODULE__.TopologySet{topology: topology}

  def agent_add(name, definition, opts \\ []),
    do:
      struct!(
        __MODULE__.AgentAdd,
        mutation_options(opts, [:count, :initial_state]) ++ [name: name, definition: definition]
      )

  def agent_update(name, changes), do: %__MODULE__.AgentUpdate{name: name, changes: changes}

  def agent_replace(name, definition, opts \\ []),
    do:
      struct!(
        __MODULE__.AgentReplace,
        mutation_options(opts, [:count, :initial_state]) ++ [name: name, definition: definition]
      )

  def agent_remove(name), do: %__MODULE__.AgentRemove{name: name}

  def route_add(path, handler \\ %{kind: :pass_through}, opts \\ []),
    do:
      struct!(
        __MODULE__.RouteAdd,
        mutation_options(opts, [:as, :defaults, :emits]) ++ [path: path, handler: handler]
      )

  def route_update(path, changes), do: %__MODULE__.RouteUpdate{path: path, changes: changes}

  def route_replace(path, handler, opts \\ []),
    do:
      struct!(
        __MODULE__.RouteReplace,
        mutation_options(opts, [:as, :defaults, :emits]) ++ [path: path, handler: handler]
      )

  def route_remove(path), do: %__MODULE__.RouteRemove{path: path}
  def routes_reorder(paths), do: %__MODULE__.RoutesReorder{paths: paths}
  def routes_set(routes), do: %__MODULE__.RoutesSet{routes: routes}

  def connection_add(path, opts),
    do:
      struct!(
        __MODULE__.ConnectionAdd,
        mutation_options(opts, [:from, :to, :delivery]) ++ [path: path]
      )

  def connection_update(path, opts),
    do:
      struct!(
        __MODULE__.ConnectionUpdate,
        mutation_options(opts, [:from, :to, :changes]) ++ [path: path]
      )

  def connection_replace(path, opts),
    do:
      struct!(
        __MODULE__.ConnectionReplace,
        mutation_options(opts, [:from, :to, :delivery]) ++ [path: path]
      )

  def connection_remove(path, opts),
    do: struct!(__MODULE__.ConnectionRemove, mutation_options(opts, [:from, :to]) ++ [path: path])

  def plugin_add(module, options \\ [], opts \\ []) do
    opts = mutation_options(opts, [:initial])

    %PluginAdd{
      module: module,
      options: options,
      initial: if(Keyword.has_key?(opts, :initial), do: {:value, opts[:initial]}, else: :default)
    }
  end

  def plugin_configure(module, options, opts \\ []),
    do: %PluginConfigure{
      module: module,
      options: options,
      migrate: mutation_options(opts, [:migrate])[:migrate]
    }

  def plugin_remove(module, opts \\ []),
    do: %PluginRemove{module: module, state: mutation_options(opts, [:state])[:state]}

  defp mutation_options(opts, allowed) do
    unless Keyword.keyword?(opts) and Enum.uniq(Keyword.keys(opts)) == Keyword.keys(opts),
      do: raise(ArgumentError, "Expected unique keyword options")

    Keyword.validate!(opts, allowed)
  end
end
