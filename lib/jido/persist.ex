defmodule Jido.Persist do
  @moduledoc """
  Coordinates hibernate/thaw operations for agents with thread support.

  This module is the **invariant enforcer** - it ensures:

  1. Journal is flushed before checkpoint
  2. Checkpoint never contains full Thread, only a pointer
  3. Thread is rehydrated on thaw

  ## API

  The primary API accepts a storage configuration tuple:

      Jido.Persist.hibernate({adapter, opts}, agent)
      Jido.Persist.thaw({adapter, opts}, agent_module, key)

  Or a Jido instance with embedded storage config:

      Jido.Persist.hibernate(jido_instance, agent)
      Jido.Persist.thaw(jido_instance, agent_module, key)

  ## hibernate/2 Flow

  1. Extract thread from `agent.state[:__thread__]`
  2. If thread exists with entries, flush journal via `adapter.append_thread/3`
  3. Call `agent_module.checkpoint/2` if implemented, else use default
  4. **Enforce invariant**: Remove `:__thread__` from state, store only thread pointer
  5. Call `adapter.put_checkpoint/3`

  ## thaw/3 Flow

  1. Call `adapter.get_checkpoint/2`
  2. If `:not_found`, return `:not_found`
  3. Call `agent_module.restore/2` if implemented, else use default
  4. If checkpoint has thread pointer, load and attach thread
  5. Verify loaded thread.rev matches checkpoint pointer rev

  ## Agent Callbacks

  Agents may optionally implement:

  - `checkpoint(agent, ctx)` - Returns `{:ok, checkpoint_data}` for custom serialization
  - `restore(checkpoint_data, ctx)` - Returns `{:ok, agent}` for custom deserialization

  If not implemented, default serialization is used.

  ## Examples

      # Using storage config tuple
      storage = {Jido.Storage.ETS, table: :my_storage}

      # Hibernate an agent
      :ok = Jido.Persist.hibernate(storage, agent)

      # Thaw an agent
      case Jido.Persist.thaw(storage, MyAgent, "agent-123") do
        {:ok, agent} -> agent
        :not_found -> start_fresh()
        {:error, :missing_thread} -> handle_missing_thread()
        {:error, :thread_mismatch} -> handle_mismatch()
      end
  """

  require Logger

  alias Jido.Thread

  @type storage_config :: {module(), keyword()}
  @type agent :: struct()
  @type agent_module :: module()
  @type key :: term()
  @type checkpoint_key :: {agent_module(), term()}

  @type thread_pointer :: %{id: String.t(), rev: non_neg_integer()}

  @type checkpoint :: %{
          version: pos_integer(),
          agent_module: agent_module(),
          id: term(),
          state: map(),
          thread: thread_pointer() | nil
        }

  @doc """
  Persists an agent to storage, flushing any pending thread entries first.

  Accepts either a `{adapter, opts}` tuple or a struct with `:storage` field.

  ## Examples

      storage = {Jido.Storage.ETS, table: :agents}
      :ok = Jido.Persist.hibernate(storage, my_agent)

  ## Returns

  - `:ok` - Successfully hibernated
  - `{:error, reason}` - Failed to hibernate
  """
  @spec hibernate(storage_config() | module() | struct(), agent()) :: :ok | {:error, term()}
  def hibernate(storage_or_instance, agent)

  def hibernate({adapter, opts}, agent) when is_atom(adapter) do
    do_hibernate(adapter, opts, agent)
  end

  def hibernate(%{storage: {adapter, opts}}, agent) do
    do_hibernate(adapter, opts, agent)
  end

  def hibernate(jido_instance, agent) when is_atom(jido_instance) do
    {adapter, opts} = jido_instance.__jido_storage__()
    do_hibernate(adapter, opts, agent)
  end

  @doc """
  Restores an agent from storage, rehydrating thread if present.

  Accepts either a `{adapter, opts}` tuple or a struct with `:storage` field.

  ## Examples

      storage = {Jido.Storage.ETS, table: :agents}
      {:ok, agent} = Jido.Persist.thaw(storage, MyAgent, "agent-123")

  ## Returns

  - `{:ok, agent}` - Successfully thawed
  - `:not_found` - No checkpoint exists for this key
  - `{:error, :missing_thread}` - Checkpoint references thread that doesn't exist
  - `{:error, :thread_mismatch}` - Loaded thread.rev != checkpoint thread.rev
  - `{:error, reason}` - Other errors
  """
  @spec thaw(storage_config() | module() | struct(), agent_module(), key()) ::
          {:ok, agent()} | :not_found | {:error, term()}
  def thaw(storage_or_instance, agent_module, key)

  def thaw({adapter, opts}, agent_module, key) when is_atom(adapter) do
    do_thaw(adapter, opts, agent_module, key)
  end

  def thaw(%{storage: {adapter, opts}}, agent_module, key) do
    do_thaw(adapter, opts, agent_module, key)
  end

  def thaw(jido_instance, agent_module, key) when is_atom(jido_instance) do
    {adapter, opts} = jido_instance.__jido_storage__()
    do_thaw(adapter, opts, agent_module, key)
  end

  # --- Private Implementation ---

  @spec do_hibernate(module(), keyword(), agent()) :: :ok | {:error, term()}
  defp do_hibernate(adapter, opts, agent) do
    agent_module = agent.__struct__
    thread = get_thread(agent)

    Logger.debug("Persist.hibernate starting for #{inspect(agent_module)} id=#{agent.id}")

    with :ok <- flush_journal(adapter, opts, thread),
         {:ok, checkpoint} <- create_checkpoint(agent_module, agent, thread),
         checkpoint_key <- make_checkpoint_key(agent_module, agent.id),
         :ok <- adapter.put_checkpoint(checkpoint_key, checkpoint, opts) do
      Logger.debug("Persist.hibernate completed for #{inspect(agent_module)} id=#{agent.id}")
      :ok
    else
      {:error, reason} = error ->
        Logger.error(
          "Persist.hibernate failed for #{inspect(agent_module)} id=#{agent.id}: #{inspect(reason)}"
        )

        error
    end
  end

  @spec do_thaw(module(), keyword(), agent_module(), key()) ::
          {:ok, agent()} | :not_found | {:error, term()}
  defp do_thaw(adapter, opts, agent_module, key) do
    checkpoint_key = make_checkpoint_key(agent_module, key)

    Logger.debug("Persist.thaw starting for #{inspect(agent_module)} key=#{inspect(key)}")

    case adapter.get_checkpoint(checkpoint_key, opts) do
      {:ok, checkpoint} ->
        restore_from_checkpoint(adapter, opts, agent_module, checkpoint)

      :not_found ->
        Logger.debug("Persist.thaw: checkpoint not found for #{inspect(checkpoint_key)}")
        :not_found

      {:error, reason} = error ->
        Logger.error(
          "Persist.thaw failed to get checkpoint for #{inspect(checkpoint_key)}: #{inspect(reason)}"
        )

        error
    end
  end

  @spec flush_journal(module(), keyword(), Thread.t() | nil) :: :ok | {:error, term()}
  defp flush_journal(_adapter, _opts, nil), do: :ok
  defp flush_journal(_adapter, _opts, %Thread{entries: []}), do: :ok

  defp flush_journal(adapter, opts, %Thread{} = thread) do
    Logger.debug("Persist: flushing #{length(thread.entries)} entries for thread #{thread.id}")

    case adapter.append_thread(thread.id, thread.entries, [{:expected_rev, 0} | opts]) do
      {:ok, _updated_thread} ->
        :ok

      {:error, :conflict} ->
        Logger.debug("Persist: conflict on append, thread may already be persisted")
        :ok

      {:error, reason} = error ->
        Logger.error(
          "Persist: failed to flush journal for thread #{thread.id}: #{inspect(reason)}"
        )

        error
    end
  end

  @spec create_checkpoint(agent_module(), agent(), Thread.t() | nil) ::
          {:ok, checkpoint()} | {:error, term()}
  defp create_checkpoint(agent_module, agent, thread) do
    ctx = %{}

    result =
      if function_exported?(agent_module, :checkpoint, 2) do
        agent_module.checkpoint(agent, ctx)
      else
        {:ok, default_checkpoint(agent, thread)}
      end

    case result do
      {:ok, checkpoint} ->
        {:ok, enforce_checkpoint_invariants(checkpoint, thread)}

      {:error, _} = error ->
        error
    end
  end

  @spec enforce_checkpoint_invariants(map(), Thread.t() | nil) :: checkpoint()
  defp enforce_checkpoint_invariants(checkpoint, thread) do
    state_without_thread = Map.delete(checkpoint[:state] || %{}, :__thread__)

    thread_pointer =
      case thread do
        nil -> nil
        %Thread{id: id, rev: rev} -> %{id: id, rev: rev}
      end

    checkpoint
    |> Map.put(:state, state_without_thread)
    |> Map.put(:thread, thread_pointer)
  end

  @spec default_checkpoint(agent(), Thread.t() | nil) :: checkpoint()
  defp default_checkpoint(agent, thread) do
    thread_pointer =
      case thread do
        nil -> nil
        %Thread{id: id, rev: rev} -> %{id: id, rev: rev}
      end

    %{
      version: 1,
      agent_module: agent.__struct__,
      id: agent.id,
      state: Map.delete(agent.state, :__thread__),
      thread: thread_pointer
    }
  end

  @spec restore_from_checkpoint(module(), keyword(), agent_module(), checkpoint()) ::
          {:ok, agent()} | {:error, term()}
  defp restore_from_checkpoint(adapter, opts, agent_module, checkpoint) do
    ctx = %{}

    with {:ok, agent} <- restore_agent(agent_module, checkpoint, ctx),
         {:ok, agent} <- rehydrate_thread(adapter, opts, agent, checkpoint) do
      Logger.debug("Persist.thaw completed for #{inspect(agent_module)} id=#{checkpoint.id}")
      {:ok, agent}
    end
  end

  @spec restore_agent(agent_module(), checkpoint(), map()) :: {:ok, agent()} | {:error, term()}
  defp restore_agent(agent_module, checkpoint, ctx) do
    if function_exported?(agent_module, :restore, 2) do
      agent_module.restore(checkpoint, ctx)
    else
      default_restore(agent_module, checkpoint)
    end
  end

  @spec default_restore(agent_module(), checkpoint()) :: {:ok, agent()} | {:error, term()}
  defp default_restore(agent_module, checkpoint) do
    case agent_module.new(id: checkpoint.id) do
      {:ok, agent} ->
        merged_state = Map.merge(agent.state, checkpoint.state || %{})
        {:ok, %{agent | state: merged_state}}

      agent when is_struct(agent) ->
        merged_state = Map.merge(agent.state, checkpoint.state || %{})
        {:ok, %{agent | state: merged_state}}

      {:error, _} = error ->
        error
    end
  end

  @spec rehydrate_thread(module(), keyword(), agent(), checkpoint()) ::
          {:ok, agent()} | {:error, term()}
  defp rehydrate_thread(_adapter, _opts, agent, %{thread: nil}), do: {:ok, agent}

  defp rehydrate_thread(adapter, opts, agent, %{thread: %{id: thread_id, rev: expected_rev}}) do
    Logger.debug("Persist: rehydrating thread #{thread_id} with expected rev=#{expected_rev}")

    case adapter.load_thread(thread_id, opts) do
      {:ok, %Thread{rev: ^expected_rev} = thread} ->
        agent_with_thread = attach_thread(agent, thread)
        {:ok, agent_with_thread}

      {:ok, %Thread{rev: actual_rev}} ->
        Logger.error(
          "Persist: thread rev mismatch for #{thread_id}: expected=#{expected_rev}, actual=#{actual_rev}"
        )

        {:error, :thread_mismatch}

      :not_found ->
        Logger.error("Persist: thread #{thread_id} not found but referenced in checkpoint")
        {:error, :missing_thread}

      {:error, reason} = error ->
        Logger.error("Persist: failed to load thread #{thread_id}: #{inspect(reason)}")
        error
    end
  end

  @spec get_thread(agent()) :: Thread.t() | nil
  defp get_thread(%{state: %{__thread__: thread}}) when is_struct(thread, Thread), do: thread
  defp get_thread(_agent), do: nil

  @spec attach_thread(agent(), Thread.t()) :: agent()
  defp attach_thread(agent, thread) do
    %{agent | state: Map.put(agent.state, :__thread__, thread)}
  end

  @spec make_checkpoint_key(agent_module(), term()) :: checkpoint_key()
  defp make_checkpoint_key(agent_module, agent_id) do
    {agent_module, agent_id}
  end
end
