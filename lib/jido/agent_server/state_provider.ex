defmodule Jido.AgentServer.StateProvider do
  @moduledoc """
  An optional state source for a durable, module-defined Agent.

  Declare a provider with `state_provider Provider, options` in the Agent's
  `state` block. Its compile callback supplies the state schema and a static
  descriptor. The descriptor stays in the Agent module. An in-memory Agent
  command does not call the provider.

  The provider can use the trusted activation address and persistence profile.
  `open/5` owns the activation boundary. Call the supplied function to create
  or restore the Jido record. `refresh/3` runs before new work, but a durable
  continuation uses the state saved at its admission.

  A provider can implement `startup_id/2` to accept a `Source` as the
  `:state` option. Return the stable ID without loading row state. During
  creation, `open/5` receives the Agent definition with that ID and a nil
  state. Load and validate the initial instance before calling the save
  function. The startup callback receives nil when the caller omits the source.

  `commit/5` must call the supplied function exactly once with the canonical
  candidate in the same transaction as its own writes. Return its payload
  only after the transaction commits. Return `{:error, {:rejected, reason}}`
  for an unchanged or rolled back write. Report uncertain commits with
  `{:error, :indeterminate}`. Jido publishes state and runs effects after
  a successful commit.
  """

  alias Jido.Agent
  alias Jido.Persistence.Config

  defmodule Source do
    @moduledoc "A provider-owned input for the Agent startup state."
    @enforce_keys [:provider, :input]
    defstruct [:provider, :input]
  end

  @type context :: %{address: Agent.Address.t(), persistence: Config.t()}
  @type result :: {:ok, term()} | {:error, term()}
  @type activation :: {:ok, Agent.t(), non_neg_integer(), non_neg_integer(), term(), map()} | {:error, term()}

  @callback compile_state!(term(), Macro.Env.t()) :: {Jido.Joi.schema(), term()}
  @callback open(term(), context(), :create | :restore, Agent.t(), (Agent.t() -> activation())) :: activation()
  @callback refresh(term(), context(), Agent.t()) :: {:ok, Agent.t()} | {:error, term()}
  @callback commit(term(), context(), Agent.t(), Agent.t(), (Agent.t() -> result())) :: result()
  @callback startup_id(term(), term()) :: {:ok, String.t()} | {:error, term()}
  @optional_callbacks startup_id: 2

  @doc false
  def startup(%Agent{id: id, state: state}, opts, _mode) when is_binary(id) and is_map(state) do
    if match?(%Source{}, opts[:state]),
      do: startup_error(:state_source_requires_definition, "Pass the Agent module when starting from a state source."),
      else: :default
  end

  def startup(source, opts, mode) do
    input = Keyword.get(opts, :state)

    case {declaration(source), input, mode} do
      {{provider, descriptor, _}, %Source{provider: provider, input: value}, mode} when mode in [nil, :create] ->
        with :ok <- check_id_override(opts),
             {:ok, id} <- startup_id(provider, descriptor, value),
             :ok <- Agent.Schema.nonempty(id),
             {:ok, definition} <- Agent.Validation.resolve(source) do
          {:ok, %{definition | id: id}}
        end

      {_, %Source{}, :restore} ->
        startup_error(:state_source_restore, "Restore the Agent with its saved address.")

      {_, %Source{}, _} ->
        startup_error(:state_provider_mismatch, "The state source must match the Agent's declared state provider.")

      {{provider, descriptor, _}, _, mode} when mode in [nil, :create] ->
        missing_source(provider, descriptor)

      _ ->
        :default
    end
  end

  @doc false
  def loads_initial_state?(agent) do
    case declaration(agent) do
      {provider, _, _} -> function_exported?(provider, :startup_id, 2)
      nil -> false
    end
  end

  defp check_id_override(opts) do
    if Keyword.has_key?(opts, :id),
      do: startup_error(:state_source_owns_id, "Omit :id. The state source supplies the Agent ID."),
      else: :ok
  end

  defp missing_source(provider, descriptor) do
    if function_exported?(provider, :startup_id, 2) do
      case provider.startup_id(descriptor, nil) do
        {:error, _} = error -> error
        _ -> startup_error(:state_source_required, "This Agent requires a startup state source.")
      end
    else
      :default
    end
  end

  defp startup_id(provider, descriptor, value) do
    if function_exported?(provider, :startup_id, 2),
      do: provider.startup_id(descriptor, value),
      else: startup_error(:state_source_unsupported, "This state provider does not accept a startup state source.")
  end

  defp startup_error(reason, message),
    do: Jido.Error.validation_result(reason, [:state], message)

  @doc false
  def configured?(agent), do: declaration(agent) != nil

  @doc false
  def open(agent, context, mode, fun) do
    case declaration(agent) do
      nil -> fun.(agent)
      {provider, descriptor, _schema} -> provider.open(descriptor, context, mode, agent, fun)
    end
  end

  @doc false
  def refresh(agent, context) do
    case declaration(agent) do
      nil -> {:ok, agent}
      {provider, descriptor, _schema} -> provider.refresh(descriptor, context, agent)
    end
  end

  @doc false
  def commit(agent, %Agent{id: id, module: module} = candidate, context, fun) do
    case declaration(agent) do
      nil ->
        fun.(candidate)

      {provider, descriptor, _schema} ->
        save = fn
          %Agent{id: ^id, module: ^module, state: state} ->
            case Agent.Validation.transition(candidate, state) do
              {:ok, canonical} -> fun.(canonical)
              {:error, _error} -> {:error, {:rejected, :invalid_provider_state}}
            end

          _agent ->
            {:error, {:rejected, :invalid_provider_identity}}
        end

        case provider.commit(descriptor, context, agent, candidate, save) do
          {:error, {:rejected, reason}} -> {:error, {:state_provider_rejected, reason}}
          result -> result
        end
    end
  end

  defp declaration(%Agent{module: module}), do: declaration(module)

  defp declaration(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__jido_state_provider__, 0),
      do: module.__jido_state_provider__()
  end

  defp declaration(_source), do: nil
end
