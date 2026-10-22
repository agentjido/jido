defmodule Jido.Agent do
  @moduledoc """
  Author Agent definitions as Maps or with the Spark DSL.

  Definitions and instances use this struct. A definition has nil `id` and
  `state`. An instance has a nonempty `id` and complete `state`, including
  Plugin-owned fields. Authoring and instance construction do not start
  processes or execute handlers. JSON uses trusted Registry references.

  Routes select one handler in declaration order. Connections select recipients
  for outputs. Providers add explicit, validated data to `extensions`.
  """
  alias Jido.Agent.{Data, Validation}
  alias Jido.Agent.Runner
  alias Jido.Signal
  alias Jido.Error

  @type t :: %__MODULE__{}

  @doc "Writes one custom portable checkpoint payload for this Agent module."
  @callback checkpoint(instance(), map()) :: {:ok, map()} | {:error, term()}

  @doc "Restores one Agent instance from a custom portable checkpoint payload."
  @callback restore(map(), map()) :: {:ok, instance()} | {:error, term()}
  @optional_callbacks checkpoint: 2, restore: 2

  @schema Zoi.struct(__MODULE__, %{
            id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
            state: Zoi.map() |> Zoi.nullable() |> Zoi.default(nil),
            module: Zoi.atom() |> Zoi.nullable() |> Zoi.default(nil),
            name: Zoi.string() |> Zoi.min(1),
            description: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
            vsn: Zoi.integer() |> Zoi.min(1) |> Zoi.default(1),
            schema: Zoi.any() |> Zoi.default(Zoi.object(%{})),
            metadata: Zoi.map() |> Zoi.default(%{}),
            signal_source: Zoi.string() |> Zoi.min(1) |> Zoi.nullable() |> Zoi.default(nil),
            routes: Zoi.list(Zoi.any()) |> Zoi.default([]),
            topology: Zoi.map() |> Zoi.default(%{}),
            extensions: Zoi.list(Zoi.any()) |> Zoi.default([])
          })
  @defaults Map.new(Zoi.Struct.struct_fields(@schema), fn
              {key, value} -> {key, value}
              key -> {key, nil}
            end)
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  @doc false
  def __schema__, do: @schema
  @doc false
  def __defaults__, do: @defaults

  @doc "Returns the state schema, including Plugin-owned fields."
  @spec schema(t()) :: Zoi.schema()
  def schema(%__MODULE__{} = agent),
    do: Validation.state_schema(agent) |> Jido.Agent.Error.unwrap!()

  @type definition :: %__MODULE__{id: nil, state: nil}
  @type instance :: %__MODULE__{id: String.t(), state: map()}

  @doc """
  Defines a compiled Agent module with the Agent DSL.

  ## Options

  - `:id` is the stable authoring Registry ID. It defaults to the module name.
  - `:name` is the required Agent name.
  - `:description` is optional display text.
  - `:vsn` is the positive definition version. It defaults to `1`.
  - `:extensions` lists the Extension or Plugin providers that add authoring
    sections or need an empty configuration.

  ## Core DSL

  Each optional core section can occur once:

      use Jido.Agent, id: "my_app/counter", name: "counter", vsn: 1

      agent do
        schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
        metadata %{domain: "counters"}
        plugin MyApp.Plugin, config: %{mode: :strict}
      end

      routes do
        signal_source "/my_app/counter"
        route "counter.add", MyApp.Add, as: :add, defaults: %{amount: 1}
      end

      topology do
        agent :workers, MyApp.Worker, count: 2

        connections do
          connect "work.ready", from: :workers, to: :root
        end
      end

  The `agent` section accepts `schema`, `metadata`, and `plugin`. The `routes`
  section accepts `signal_source` and ordered `route` declarations. A route can
  use an Action or Flow module, an inline `action` or `transform`, a
  `Jido.SignalAction` module, or no handler for pass-through. Route options are
  `:as`, `:defaults`, `:emits`, and `:via`; `:via` is only for a
  `Jido.SignalAction` route. An `:as` value must start with a lowercase letter
  and contain only lowercase letters, digits, and underscores.

  The `topology` section accepts named `agent` members and a `connections`
  section with `connect` declarations. `state/1` creates a reference to one
  parent state field. Selected providers can add their own sections and
  imports.

  Compilation lowers this DSL to the same canonical value that `define/1`
  builds from a map.
  """
  defmacro __using__(opts) do
    opts = options!(opts, __CALLER__)

    imports =
      Enum.flat_map(Keyword.get(opts, :extensions, []), fn provider ->
        if function_exported?(provider, :authoring_imports, 0),
          do: provider.authoring_imports(),
          else: []
      end)

    quote do
      use Jido.Action.Inline
      use Jido.Agent.DSL, unquote(Macro.escape(opts))
      import Jido.Agent.DSL.Macros
      import Jido.Agent.Directive, only: [emit: 1, emit: 2]
      import Jido.Config, only: [env: 1]
      unquote_splicing(Enum.map(imports, fn module -> quote do: import(unquote(module)) end))
    end
  end

  @doc false
  def options!(quoted, caller) do
    {opts, _binding} = Code.eval_quoted(quoted, [], caller)

    unless Keyword.keyword?(opts) and Enum.uniq(Keyword.keys(opts)) == Keyword.keys(opts),
      do: raise(ArgumentError, "Agent requires unique keyword options")

    opts = Keyword.put_new(opts, :id, Atom.to_string(caller.module))

    with :ok <- Jido.Authoring.Registry.validate_identifier(opts[:id]),
         {:ok, _providers} <-
           Jido.Agent.Extension.providers(Keyword.get(opts, :extensions, [])) do
      opts
    else
      {:error, error} -> raise error
    end
  end

  @doc "Builds and validates a neutral Agent definition from a plain map."
  @spec define(map()) :: {:ok, definition()} | {:error, term()}
  def define(map), do: Validation.define(map)

  @doc "Builds one neutral Agent definition or raises its validation error."
  @spec define!(map()) :: definition() | no_return()
  def define!(map), do: map |> define() |> Jido.Agent.Error.unwrap!()

  @doc "Validates a definition or instance, including schema, routes, and provider data."
  @spec validate(term()) :: {:ok, t()} | {:error, term()}
  def validate(value), do: Validation.validate(value)

  @doc "Checks definition shape only. Use validate/1 to check the field values."
  @spec definition?(term()) :: boolean()
  def definition?(%__MODULE__{id: nil, state: nil}), do: true
  def definition?(_), do: false

  @doc "Checks instance shape only. Use validate/1 to check complete state and definition data."
  @spec instance?(term()) :: boolean()
  def instance?(%__MODULE__{id: id, state: state})
      when is_binary(id) and byte_size(id) > 0 and is_map(state) and not is_struct(state),
      do: true

  def instance?(_), do: false

  @doc "Returns the neutral definition for an Agent value or compiled Agent module."
  @spec definition(t() | module()) :: definition()
  def definition(%__MODULE__{} = value), do: %{value | id: nil, state: nil}

  def definition(module) when is_atom(module),
    do: module |> Validation.resolve() |> Jido.Agent.Error.unwrap!()

  @doc "Builds and validates one Agent instance from a definition or compiled Agent module."
  @spec instantiate(definition() | module(), keyword() | map()) ::
          {:ok, instance()} | {:error, term()}
  def instantiate(source, opts \\ []), do: Validation.instantiate(source, opts)

  @doc "Builds one Agent instance or raises its validation error."
  @spec instantiate!(definition() | module(), keyword() | map()) :: instance() | no_return()
  def instantiate!(source, opts \\ []),
    do: source |> instantiate(opts) |> Jido.Agent.Error.unwrap!()

  @doc "Applies ordered data mutations and returns the candidate and its final Diff."
  @spec mutate(t(), [Jido.Agent.Directive.t()]) ::
          {:ok, t(), Jido.Agent.Diff.t()} | {:error, term()}
  def mutate(%__MODULE__{} = agent, directives), do: Jido.Agent.Mutation.apply(agent, directives)

  @doc false
  def runtime_plugins(%__MODULE__{extensions: entries}) do
    Enum.flat_map(entries, fn entry ->
      module = entry.provider.runtime_support()

      if Code.ensure_loaded?(module) and function_exported?(module, :__jido_plugin__, 0),
        do: [{module, Enum.sort(entry.data)}],
        else: []
    end)
  end

  @doc false
  def validate_runtime_support(%__MODULE__{extensions: entries}) do
    unknown =
      Enum.find(entries, fn entry ->
        module = entry.provider.runtime_support()

        module != :none and
          not (Code.ensure_loaded?(module) and function_exported?(module, :__jido_plugin__, 0))
      end)

    if unknown,
      do:
        Jido.Agent.Error.fail(
          :runtime_support_not_available,
          [:extensions],
          "Provider runtime support has no Plugin adapter",
          %{provider: unknown.provider}
        ),
      else: :ok
  end

  @doc false
  @spec input_signal(definition(), String.t(), map(), keyword() | map()) ::
          {:ok, Signal.t()} | {:error, term()}
  def input_signal(definition, type, data, opts \\ []) do
    with {:ok, opts} <-
           Validation.options(opts, [:source, :id, :time, :subject, :datacontenttype]),
         source = Map.get(opts, :source, definition.signal_source),
         :ok <- Jido.Agent.Error.at(Jido.Agent.Data.nonempty(source), :source),
         :ok <- Jido.Agent.Data.plain_map(data) do
      Jido.Signal.new(type, data, Map.put(opts, :source, source))
    end
  end

  @doc false
  @spec input_signal!(definition(), String.t(), map(), keyword() | map()) ::
          Signal.t() | no_return()
  def input_signal!(definition, type, data, opts \\ []) do
    case input_signal(definition, type, data, opts) do
      {:ok, signal} -> signal
      {:error, %{__exception__: true} = error} -> raise error
      {:error, reason} -> raise ArgumentError, "invalid input Signal: #{inspect(reason)}"
    end
  end

  @doc false
  @spec transition(instance(), term()) :: {:ok, instance()} | {:error, Exception.t()}
  def transition(%__MODULE__{} = agent, next_state) do
    with {:ok, agent, _specs, schema} <- Validation.validate_instance_with_plugins(agent) do
      transition_validated(agent, next_state, schema)
    end
  end

  @doc false
  @spec transition_validated(instance(), term(), Zoi.schema()) ::
          {:ok, instance()} | {:error, Exception.t()}
  def transition_validated(%__MODULE__{} = agent, next_state, schema) do
    with :ok <- Jido.Agent.Error.at(Data.complete(schema, next_state), :state) do
      {:ok, %{agent | state: next_state}}
    end
  end

  @doc """
  Replaces supplied top-level domain fields and validates the complete next state.

  Fields not supplied retain their values. A supplied nested map replaces the
  previous map. To retain nested values, merge them before calling this function:

      config = Map.merge(agent.state.config, %{enabled: true})
      Jido.Agent.set(agent, config: config)

  Plugin-owned fields cannot be set with this function.
  """
  @spec set(instance(), map() | keyword()) :: {:ok, instance()} | {:error, Exception.t()}
  def set(%__MODULE__{} = agent, attrs) do
    with {:ok, attrs} <- normalize_domain_attrs(attrs),
         :ok <- validate_domain_attrs(agent, attrs) do
      if not is_map(agent.state) or is_struct(agent.state) do
        invalid("Agent.set/2 requires an instance", %{id: agent.id, state: agent.state})
      else
        transition(agent, Map.merge(agent.state, attrs))
      end
    end
  end

  @doc """
  Runs one complete Turn through `Jido.Exec.run/4` without an AgentServer.

  Returns the next Agent value and validated Directives. It does not dispatch
  those Directives, save state, resume work, or deduplicate inputs.

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
