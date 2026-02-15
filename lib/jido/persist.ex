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
      Jido.Persist.hibernate({adapter, opts}, agent_module, key, agent)
      Jido.Persist.thaw({adapter, opts}, agent_module, key)

  Or a Jido instance with embedded storage config:

      Jido.Persist.hibernate(jido_instance, agent)
      Jido.Persist.hibernate(jido_instance, agent_module, key, agent)
      Jido.Persist.thaw(jido_instance, agent_module, key)

  ## hibernate Flow

  1. Extract thread from `agent.state[:__thread__]`
  2. Flush only missing thread entries via `adapter.append_thread/3`
  3. Call `agent_module.checkpoint/2` if implemented, else use default
  4. **Enforce invariant**: Remove `:__thread__` from state, store only thread pointer
  5. Call `adapter.put_checkpoint/3`

  ## thaw/3 Flow

  1. Call `adapter.get_checkpoint/2`
  2. If missing, return `{:error, :not_found}`
  3. Call `agent_module.restore/2` if implemented, else use default
  4. If checkpoint has thread pointer, load and attach thread
  5. Verify loaded thread.rev matches checkpoint pointer rev

  ## Agent Callbacks

  Agents may optionally implement:

  - `checkpoint(agent, ctx)` - Returns `{:ok, checkpoint_data}` for custom serialization
  - `restore(checkpoint_data, ctx)` - Returns `{:ok, agent}` for custom deserialization

  If not implemented, default serialization is used.
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

  Accepts a `{storage_adapter, opts}` tuple, a storage adapter module,
  a map/struct with `:storage`, or a Jido instance module.
  """
  @spec hibernate(storage_config() | module() | struct(), agent()) :: :ok | {:error, term()}
  def hibernate(storage_or_instance, agent) do
    with {:ok, {agent_module, key}} <- resolve_agent_identity(agent),
         {:ok, {adapter, opts}} <- resolve_storage(storage_or_instance) do
      do_hibernate(adapter, opts, agent_module, key, agent)
    end
  end

  @doc """
  Persists an agent using an explicit `{agent_module, key}` identity.

  This is primarily used by keyed lifecycle managers that persist with pool keys.
  """
  @spec hibernate(storage_config() | module() | struct(), agent_module(), key(), agent()) ::
          :ok | {:error, term()}
  def hibernate(storage_or_instance, agent_module, key, agent) do
    with {:ok, {adapter, opts}} <- resolve_storage(storage_or_instance) do
      do_hibernate(adapter, opts, agent_module, key, agent)
    end
  end

  @doc """
  Restores an agent from storage, rehydrating thread if present.

  Accepts a `{storage_adapter, opts}` tuple, a storage adapter module,
  a map/struct with `:storage`, or a Jido instance module.
  """
  @spec thaw(storage_config() | module() | struct(), agent_module(), key()) ::
          {:ok, agent()} | {:error, term()}
  def thaw(storage_or_instance, agent_module, key) do
    with {:ok, {adapter, opts}} <- resolve_storage(storage_or_instance) do
      do_thaw(adapter, opts, agent_module, key)
    end
  end

  # --- Private Implementation ---

  @spec do_hibernate(module(), keyword(), agent_module(), key(), agent()) ::
          :ok | {:error, term()}
  defp do_hibernate(adapter, opts, agent_module, key, agent) do
    thread = get_thread(agent)

    Logger.debug("Persist.hibernate starting for #{inspect(agent_module)} key=#{inspect(key)}")

    with :ok <- flush_journal(adapter, opts, thread),
         {:ok, checkpoint} <- create_checkpoint(agent_module, agent, thread),
         checkpoint_key <- make_checkpoint_key(agent_module, key),
         :ok <- adapter.put_checkpoint(checkpoint_key, checkpoint, opts) do
      Logger.debug("Persist.hibernate completed for #{inspect(agent_module)} key=#{inspect(key)}")
      :ok
    else
      {:error, reason} = error ->
        Logger.error(
          "Persist.hibernate failed for #{inspect(agent_module)} key=#{inspect(key)}: #{inspect(reason)}"
        )

        error
    end
  end

  @spec do_thaw(module(), keyword(), agent_module(), key()) :: {:ok, agent()} | {:error, term()}
  defp do_thaw(adapter, opts, agent_module, key) do
    checkpoint_key = make_checkpoint_key(agent_module, key)

    Logger.debug("Persist.thaw starting for #{inspect(agent_module)} key=#{inspect(key)}")

    case Jido.Storage.fetch_checkpoint(adapter, checkpoint_key, opts) do
      {:ok, checkpoint} ->
        restore_from_checkpoint(adapter, opts, agent_module, checkpoint)

      {:error, :not_found} ->
        Logger.debug("Persist.thaw: checkpoint not found for #{inspect(checkpoint_key)}")
        {:error, :not_found}

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
    with :ok <- validate_local_thread(thread),
         {:ok, stored_rev} <- get_stored_thread_rev(adapter, opts, thread.id),
         :ok <- append_missing_entries(adapter, opts, thread, stored_rev) do
      :ok
    end
  end

  @spec validate_local_thread(Thread.t()) :: :ok | {:error, term()}
  defp validate_local_thread(%Thread{} = thread) do
    entry_count = length(thread.entries)

    if thread.rev == entry_count do
      :ok
    else
      Logger.error(
        "Persist: invalid local thread revision for #{thread.id}: rev=#{thread.rev}, entries=#{entry_count}"
      )

      {:error, :invalid_thread_revision}
    end
  end

  @spec get_stored_thread_rev(module(), keyword(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp get_stored_thread_rev(adapter, opts, thread_id) do
    case Jido.Storage.fetch_thread(adapter, thread_id, opts) do
      {:ok, %Thread{rev: stored_rev}} ->
        {:ok, stored_rev}

      {:error, :not_found} ->
        {:ok, 0}

      {:error, _reason} = error ->
        error
    end
  end

  @spec append_missing_entries(module(), keyword(), Thread.t(), non_neg_integer()) ::
          :ok | {:error, term()}
  defp append_missing_entries(adapter, opts, %Thread{} = thread, stored_rev) do
    local_rev = thread.rev
    entry_count = length(thread.entries)

    cond do
      stored_rev > local_rev ->
        Logger.error(
          "Persist: thread rev regression for #{thread.id}: local_rev=#{local_rev}, stored_rev=#{stored_rev}"
        )

        {:error, :thread_rev_regression}

      stored_rev > entry_count ->
        Logger.error(
          "Persist: thread history truncated for #{thread.id}: entry_count=#{entry_count}, stored_rev=#{stored_rev}"
        )

        {:error, :thread_history_truncated}

      stored_rev == local_rev ->
        Logger.debug("Persist: thread #{thread.id} already persisted at rev=#{stored_rev}")
        :ok

      true ->
        missing_entries = Enum.drop(thread.entries, stored_rev)

        append_opts =
          [{:expected_rev, stored_rev}]
          |> maybe_put_thread_metadata(stored_rev, thread.metadata)
          |> Kernel.++(opts)

        Logger.debug(
          "Persist: flushing #{length(missing_entries)} new entries for thread #{thread.id} from rev=#{stored_rev}"
        )

        case adapter.append_thread(thread.id, missing_entries, append_opts) do
          {:ok, _updated_thread} ->
            :ok

          {:error, :conflict} ->
            handle_thread_append_conflict(adapter, opts, thread.id, local_rev)

          {:error, reason} = error ->
            Logger.error(
              "Persist: failed to flush journal for thread #{thread.id}: #{inspect(reason)}"
            )

            error
        end
    end
  end

  @spec maybe_put_thread_metadata(keyword(), non_neg_integer(), map()) :: keyword()
  defp maybe_put_thread_metadata(opts, 0, metadata) when is_map(metadata),
    do: [{:metadata, metadata} | opts]

  defp maybe_put_thread_metadata(opts, _stored_rev, _metadata), do: opts

  @spec handle_thread_append_conflict(module(), keyword(), String.t(), non_neg_integer()) ::
          :ok | {:error, term()}
  defp handle_thread_append_conflict(adapter, opts, thread_id, local_rev) do
    case Jido.Storage.fetch_thread(adapter, thread_id, opts) do
      {:ok, %Thread{rev: stored_rev}} when stored_rev >= local_rev ->
        Logger.debug(
          "Persist: append conflict resolved for #{thread_id}; stored_rev=#{stored_rev} >= local_rev=#{local_rev}"
        )

        :ok

      {:ok, %Thread{rev: stored_rev}} ->
        Logger.error(
          "Persist: append conflict for #{thread_id}; stored_rev=#{stored_rev}, local_rev=#{local_rev}"
        )

        {:error, :conflict}

      {:error, reason} = error ->
        Logger.error(
          "Persist: append conflict but failed to reload thread #{thread_id}: #{inspect(reason)}"
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
        {:ok, default_checkpoint(agent_module, agent, thread)}
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

  @spec default_checkpoint(agent_module(), agent(), Thread.t() | nil) :: checkpoint()
  defp default_checkpoint(agent_module, agent, thread) do
    thread_pointer =
      case thread do
        nil -> nil
        %Thread{id: id, rev: rev} -> %{id: id, rev: rev}
      end

    %{
      version: 1,
      agent_module: agent_module,
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

    case Jido.Storage.fetch_thread(adapter, thread_id, opts) do
      {:ok, %Thread{rev: ^expected_rev} = thread} ->
        agent_with_thread = attach_thread(agent, thread)
        {:ok, agent_with_thread}

      {:ok, %Thread{rev: actual_rev}} ->
        Logger.error(
          "Persist: thread rev mismatch for #{thread_id}: expected=#{expected_rev}, actual=#{actual_rev}"
        )

        {:error, :thread_mismatch}

      {:error, :not_found} ->
        Logger.error("Persist: thread #{thread_id} not found but referenced in checkpoint")
        {:error, :missing_thread}

      {:error, reason} = error ->
        Logger.error("Persist: failed to load thread #{thread_id}: #{inspect(reason)}")
        error
    end
  end

  @spec resolve_storage(storage_config() | module() | struct()) ::
          {:ok, storage_config()} | {:error, term()}
  defp resolve_storage({adapter, opts}) when is_atom(adapter) and is_list(opts),
    do: {:ok, {adapter, opts}}

  defp resolve_storage(%{storage: storage}), do: resolve_storage(storage)

  defp resolve_storage(storage) when is_atom(storage) do
    cond do
      function_exported?(storage, :__jido_storage__, 0) ->
        {:ok, storage.__jido_storage__()}

      function_exported?(storage, :get_checkpoint, 2) and
        function_exported?(storage, :put_checkpoint, 3) and
        function_exported?(storage, :load_thread, 2) and
          function_exported?(storage, :append_thread, 3) ->
        {:ok, {storage, []}}

      true ->
        {:error, :invalid_storage}
    end
  end

  defp resolve_storage(_), do: {:error, :invalid_storage}

  @spec resolve_agent_identity(agent()) :: {:ok, {agent_module(), key()}} | {:error, term()}
  defp resolve_agent_identity(%{id: id} = agent) when not is_nil(id) do
    agent_module =
      case Map.get(agent, :agent_module) do
        mod when is_atom(mod) -> mod
        _ -> agent.__struct__
      end

    {:ok, {agent_module, id}}
  end

  defp resolve_agent_identity(%{id: nil}), do: {:error, :missing_agent_id}
  defp resolve_agent_identity(_), do: {:error, :invalid_agent}

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
