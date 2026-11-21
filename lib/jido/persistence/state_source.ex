defmodule Jido.Persistence.StateSource do
  @moduledoc """
  An optional state source for a durable, module-defined Agent.

  A registered Plugin can declare the domain schema and a static descriptor
  with `state_source Provider, options` in the Agent's `state` block.
  In-memory Agent commands use the state already present on the Agent.

  The provider can use the trusted activation address and persistence profile.
  `open/5` can wrap activation in a transaction. On create, call the supplied
  function with the initial projection. On restore, pass a function that receives
  the saved Agent and Turn receipt and returns an updated projection. Return
  the supplied function's opaque success value after activation succeeds.
  `refresh/3` runs before new work. A durable continuation uses the state
  saved at its admission.

  A provider can implement `startup_id/2` to accept a `Source` as the
  `:state` option. Return the stable ID without loading row state. During
  creation, `open/5` receives the Agent definition with that ID and a nil
  state. Load its projection before calling the supplied function. Jido
  initializes the instance and validates its state. The startup callback receives
  nil when the caller omits the source.

  `apply_state/5` runs in the transaction opened by the compatible persistence
  adapter. It returns a state projection and an optional notification function.
  Projections contain only fields declared by the source's object schema.
  Preserve the candidate's writable values. The source can return generated
  read-only values, such as a row version, in the resulting Agent.
  Persistence validates the state and saves the checkpoint and receipt before
  the transaction closes. It runs the function after confirmed commit.
  """

  alias Jido.Agent
  alias Jido.Persistence.{Config, TurnTransaction}

  defmodule Source do
    @moduledoc "A provider-owned input for the Agent startup state."
    @enforce_keys [:provider, :input]
    defstruct [:provider, :input]
  end

  @type context :: %{address: Agent.Address.t(), persistence: Config.t()}
  @type activation :: {:ok, Agent.t(), non_neg_integer(), non_neg_integer(), term(), map()} | {:error, term()}
  @type projection :: {:ok, map()} | {:error, term()}
  @type restore_projection :: (Agent.t(), term() -> projection())

  @type activation_result :: {:ok, reference()} | {:error, term()}

  @callback open(
              term(),
              context(),
              :create | :restore,
              Agent.t(),
              (map() | restore_projection() -> activation_result())
            ) :: activation_result()
  @callback refresh(term(), context(), Agent.t()) :: projection()
  @callback apply_state(term(), context(), Agent.t(), Agent.t(), transaction :: term()) ::
              {:ok, map(), (-> term()) | nil} | {:error, term()}
  @callback startup_id(term(), term()) :: {:ok, String.t()} | {:error, term()}
  @optional_callbacks startup_id: 2

  @doc false
  def startup(%Agent{id: id, state: state} = agent, opts, mode) when is_binary(id) and is_map(state) do
    case {declaration(agent), opts[:state], mode} do
      {_, %Source{}, _} ->
        startup_error(:state_source_requires_definition, "Pass the Agent module when starting from a state source.")

      {{provider, descriptor, _}, _, mode} when mode in [nil, :create] ->
        missing_source(provider, descriptor)

      _ ->
        :default
    end
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
  @spec open(Agent.t(), context(), :create | :restore, (Agent.t() -> activation())) :: activation()
  def open(agent, context, mode, fun) do
    case declaration(agent) do
      nil ->
        fun.(agent)

      {provider, descriptor, schema} ->
        with :ok <- TurnTransaction.supported(context.persistence) do
          open_projection(provider, descriptor, context, mode, agent, activation(mode, agent, schema, fun))
        end
    end
  end

  defp open_projection(provider, descriptor, context, mode, agent, activate) do
    ref = make_ref()
    owner = self()

    # Only Jido can publish the activation record. The source returns a
    # receipt from the same process that owns its activation transaction.
    try do
      case provider.open(descriptor, context, mode, agent, &activate_once(ref, owner, activate, &1)) do
        {:ok, ^ref} -> Process.get(ref, {:error, :invalid_state_source_activation})
        {:error, _reason} = error -> error
        _other -> {:error, :invalid_state_source_activation}
      end
    after
      Process.delete(ref)
    end
  end

  defp activate_once(ref, owner, activate, projection) when owner == self() do
    if Process.get(ref) do
      {:error, :invalid_state_source_activation}
    else
      Process.put(ref, :activating)

      case activate.(projection) do
        {:ok, _, _, _, _, _} = result ->
          Process.put(ref, result)
          {:ok, ref}

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp activate_once(_ref, _owner, _activate, _projection), do: {:error, :invalid_state_source_activation}

  defp activation(:create, agent, schema, fun) do
    fn projection ->
      with :ok <- check_projection(projection, schema),
           {:ok, agent} <- initialize(agent, projection),
           {:ok, agent} <- project(agent, projection, schema),
           do: fun.(agent)
    end
  end

  defp activation(:restore, agent, schema, fun) do
    fn
      refresh when is_function(refresh, 2) ->
        with {:ok, saved, revision, agent_revision, receipt, handoffs} <- fun.(agent),
             {:ok, projection} <- refresh.(saved, receipt),
             {:ok, restored} <- project(saved, projection, schema) do
          {:ok, restored, revision, agent_revision, receipt, handoffs}
        end

      _ ->
        {:error, :invalid_state_source_activation}
    end
  end

  defp initialize(%Agent{state: nil} = agent, projection),
    do: Agent.instantiate(Agent.definition(agent), id: agent.id, state: projection)

  defp initialize(agent, _projection), do: {:ok, agent}

  @doc false
  def refresh(agent, context) do
    case declaration(agent) do
      nil ->
        {:ok, agent}

      {provider, descriptor, schema} ->
        with {:ok, projection} <- provider.refresh(descriptor, context, agent),
             do: project(agent, projection, schema)
    end
  end

  @doc false
  def apply({provider, descriptor, schema}, context, before, candidate, tx) do
    case provider.apply_state(descriptor, context, before, candidate, tx) do
      {:ok, projection, notify} when is_nil(notify) or is_function(notify, 0) ->
        case project(candidate, projection, schema) do
          {:ok, canonical} -> {:ok, canonical, notify}
          {:error, reason} -> rejected(reason)
        end

      {:error, {:rejected, reason}} ->
        rejected(reason)

      {:error, _reason} = error ->
        error

      _other ->
        rejected(:invalid_provider_result)
    end
  end

  defp rejected(reason), do: {:error, {:state_provider_rejected, reason}}

  defp project(agent, projection, schema) do
    with :ok <- check_projection(projection, schema) do
      case Agent.Validation.transition(agent, Map.merge(agent.state, projection)) do
        {:ok, agent} -> {:ok, agent}
        {:error, _error} -> {:error, :invalid_provider_state}
      end
    end
  end

  defp check_projection(projection, schema) when is_map(projection) and not is_struct(projection) do
    {:ok, fields} = Jido.Joi.Schema.fields(schema)

    case Enum.sort(Map.keys(projection) -- Enum.map(fields, &elem(&1, 0))) do
      [] -> :ok
      undeclared -> {:error, {:state_source_undeclared_fields, undeclared}}
    end
  end

  defp check_projection(_projection, _schema), do: {:error, :invalid_provider_state}

  @doc false
  def binding(agent), do: declaration(agent)

  defp declaration(%Agent{module: module}), do: declaration(module)

  defp declaration(module), do: Jido.Agent.DSL.State.declaration(module)
end
