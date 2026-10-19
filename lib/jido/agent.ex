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
  @callback checkpoint(instance(), map()) :: {:ok, map()} | {:error, term()}
  @callback restore(map(), map()) :: {:ok, instance()} | {:error, term()}
  @optional_callbacks checkpoint: 2, restore: 2

  @schema Zoi.struct(__MODULE__, %{
            id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
            state: Zoi.map() |> Zoi.nullable() |> Zoi.default(nil),
            module: Zoi.atom() |> Zoi.nullable() |> Zoi.default(nil),
            name: Zoi.string(),
            description: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
            vsn: Zoi.integer() |> Zoi.default(1),
            schema: Zoi.any(),
            metadata: Zoi.map() |> Zoi.default(%{}),
            signal_source: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
            routes: Zoi.list(Zoi.any()) |> Zoi.default([]),
            topology: Zoi.map(),
            extensions: Zoi.list(Zoi.any()) |> Zoi.default([])
          })
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  @doc false
  def __schema__, do: @schema

  @doc "Returns the state schema, including Plugin-owned fields."
  def schema(%__MODULE__{} = agent),
    do: Validation.state_schema(agent) |> Jido.Agent.Error.unwrap!()

  @type definition :: %__MODULE__{id: nil, state: nil}
  @type instance :: %__MODULE__{id: String.t(), state: map()}

  defmacro __using__(opts) do
    opts = Jido.Agent.DSL.Discovery.options!(opts, __CALLER__)

    imports =
      Enum.flat_map(opts[:extensions], fn provider ->
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

  def define(map), do: Validation.define(map)
  def define!(map), do: map |> define() |> Jido.Agent.Error.unwrap!()

  @doc "Validates a definition or instance, including schema, routes, and provider data."
  def validate(value), do: Validation.validate(value)

  @doc "Checks definition shape only. Use validate/1 to check the field values."
  def definition?(%__MODULE__{id: nil, state: nil}), do: true
  def definition?(_), do: false

  @doc "Checks instance shape only. Use validate/1 to check complete state and definition data."
  def instance?(%__MODULE__{id: id, state: state})
      when is_binary(id) and byte_size(id) > 0 and is_map(state) and not is_struct(state),
      do: true

  def instance?(_), do: false

  def definition(%__MODULE__{} = value), do: %{value | id: nil, state: nil}

  def definition(module) when is_atom(module),
    do: module |> Validation.resolve() |> Jido.Agent.Error.unwrap!()

  def instantiate(source, opts \\ []), do: Validation.instantiate(source, opts)

  def instantiate!(source, opts \\ []),
    do: source |> instantiate(opts) |> Jido.Agent.Error.unwrap!()

  @doc "Applies ordered data mutations and returns the candidate and its final Diff."
  def mutate(%__MODULE__{} = agent, directives), do: Jido.Agent.Mutation.apply(agent, directives)

  @doc "Returns runtime Plugin declarations from provider contributions."
  def runtime_plugins(%__MODULE__{extensions: entries}) do
    Enum.flat_map(entries, fn entry ->
      case entry.provider.runtime_support() do
        :none ->
          []

        module ->
          if Code.ensure_loaded?(module) and function_exported?(module, :__jido_plugin__, 0),
            do: [{module, Enum.sort(entry.data)}],
            else: []
      end
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

  @doc "Builds a Signal for a declared helper. It does not select or run a handler."
  def input_signal(definition, type, data, opts \\ []) do
    with {:ok, opts} <-
           Validation.options(opts, [:source, :id, :time, :subject, :datacontenttype]),
         source = Map.get(opts, :source, definition.signal_source),
         :ok <- Jido.Agent.Error.at(Jido.Agent.Data.nonempty(source), :source),
         :ok <- Jido.Agent.Data.plain_map(data) do
      Jido.Signal.new(type, data, Map.put(opts, :source, source))
    end
  end

  @doc "Exports an Agent definition or instance as a JSON string."
  def to_json(agent, registry) do
    with {:ok, document} <- Jido.Agent.Codec.encode(agent, registry),
         do: Jason.encode(document)
  end

  @doc "Imports a JSON string through a trusted Registry and validates the Agent."
  def from_json(json, registry), do: Jido.Agent.Codec.from_json(json, registry)

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
