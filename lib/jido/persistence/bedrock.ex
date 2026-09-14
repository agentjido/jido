defmodule Jido.Persistence.Bedrock do
  @moduledoc """
  Bedrock KV persistence adapter for binary keys and values.

  This adapter supports Bedrock `0.7.2` and later `0.7.x` releases. The required `:repo` option must be a
  loaded module created with `use Bedrock.Repo`. The host application must
  supervise the matching Bedrock cluster. The host must add Bedrock `0.7.2` or
  later `0.7.x` and Bedrock Raft `0.10.x`. Bedrock is
  optional, so applications that do not select this adapter do not need it.

  The optional `:prefix` is a non-empty binary. It defaults to
  `"jido:persistence:"`. The optional `:timeout_in_ms` is a positive integer
  or `:infinity`. It defaults to `5_000`.

  A compare-and-swap operation uses one Bedrock transaction. Its normal
  `Repo.get/1` read adds a read conflict, and `Repo.put/2` writes the new exact
  bytes in the same transaction. A value mismatch performs no write and
  returns `{:error, :conflict}`.

  Bedrock retries transaction commit failures by default. A commit timeout can
  have an unknown result. A retry could then see the value from the first
  attempt and report a false conflict. This adapter therefore sets
  `retry_limit: 0` for every write transaction. A resolver abort is a confirmed
  conflict. Every other write transaction failure is indeterminate. This
  keeps Jido's write-result contract intact.

  Bedrock accepts keys of at most 16 KiB and values of at most 128 KiB. The
  adapter checks these limits before it starts a transaction. It runs each
  transaction in a fresh process so an application Bedrock transaction cannot
  turn an adapter write into an uncommitted nested transaction.

  Bedrock `0.7.x` provides strictly serializable transactions. It uses the
  Bedrock Raft `0.10.x` client API. A successful Bedrock commit is acknowledged
  after every required log has appended and synced its write-ahead log. The
  Bedrock cluster configuration controls the durability profile. Use Bedrock's
  strict durability mode for production. The adapter does not make a relaxed
  Bedrock cluster durable.
  """

  @behaviour Jido.Persistence.Adapter

  @default_prefix "jido:persistence:"
  @default_timeout_in_ms 5_000
  @max_key_bytes 16 * 1024
  @max_value_bytes 128 * 1024
  @bedrock_version_requirement "~> 0.7.2"
  @bedrock_raft_version_requirement "~> 0.10.0"
  @option_keys [:prefix, :repo, :timeout_in_ms]
  @repo_functions [__cluster__: 0, clear: 1, get: 1, put: 2, transact: 2]
  @bedrock_retry_abort_message "Transaction retry limit exceeded after 0 attempts. Last error: :aborted"

  @impl true
  def validate_options(opts) do
    with :ok <- validate_keyword_options(opts),
         :ok <- validate_duplicate_options(opts),
         :ok <- validate_known_options(opts),
         :ok <- validate_dependencies(),
         :ok <- validate_repo_option(opts),
         :ok <- validate_prefix_option(opts) do
      validate_timeout_option(opts)
    end
  end

  @impl true
  def get(key, opts) when is_binary(key) and is_list(opts) do
    validate_options!(opts)

    with {:ok, storage_key} <- storage_key(key, opts) do
      repo = Keyword.fetch!(opts, :repo)
      token = make_ref()

      result =
        isolated_transaction(repo, read_transaction_options(opts), fn ->
          {:ok, {__MODULE__, :read, token, repo.get(storage_key)}}
        end)

      case result do
        {:return, {:ok, {__MODULE__, :read, ^token, nil}}} ->
          {:error, :not_found}

        {:return, {:ok, {__MODULE__, :read, ^token, value}}} when is_binary(value) ->
          {:ok, value}

        {:return, {:ok, {__MODULE__, :read, ^token, invalid}}} ->
          {:error, {:invalid_bedrock_value, invalid}}

        {:return, returned} ->
          {:error, {:invalid_bedrock_result, returned}}

        {:fault, kind, reason} ->
          {:error, {:bedrock_transaction_failed, kind, reason}}
      end
    end
  end

  @impl true
  def put(key, value, opts)
      when is_binary(key) and is_binary(value) and is_list(opts) do
    validate_options!(opts)

    with {:ok, storage_key} <- storage_key(key, opts),
         :ok <- validate_value_size(value) do
      write(repo(opts), opts, fn repo, token ->
        put_value(repo, storage_key, value, token)
      end)
    end
  end

  @impl true
  def compare_and_swap(key, expected, value, opts)
      when is_binary(key) and (expected == :not_found or is_binary(expected)) and
             is_binary(value) and is_list(opts) do
    validate_options!(opts)

    with {:ok, storage_key} <- storage_key(key, opts),
         :ok <- validate_value_size(value) do
      do_compare_and_swap(repo(opts), storage_key, expected, value, opts)
    end
  end

  @impl true
  def delete(key, opts) when is_binary(key) and is_list(opts) do
    validate_options!(opts)

    with {:ok, storage_key} <- storage_key(key, opts) do
      write(repo(opts), opts, fn repo, token ->
        clear_value(repo, storage_key, token)
      end)
    end
  end

  defp do_compare_and_swap(repo, storage_key, expected, value, opts) do
    token = make_ref()

    result =
      isolated_transaction(repo, write_transaction_options(opts), fn ->
        compare_current_value(repo, storage_key, expected, value, token)
      end)

    classify_compare_result(result, token)
  end

  defp compare_current_value(repo, key, expected, value, token) do
    case repo.get(key) do
      current when is_nil(current) or is_binary(current) ->
        compare_and_write(repo, key, current, expected, value, token)

      invalid ->
        {:error, {__MODULE__, :invalid_value, token, invalid}}
    end
  end

  defp classify_compare_result({:return, {:ok, {__MODULE__, :written, token}}}, token),
    do: :ok

  defp classify_compare_result({:return, {:error, {__MODULE__, :conflict, token}}}, token),
    do: {:error, :conflict}

  defp classify_compare_result(
         {:fault, :error, %RuntimeError{message: @bedrock_retry_abort_message}},
         _token
       ),
       do: {:error, :conflict}

  defp classify_compare_result(other, _token), do: indeterminate(other)

  defp compare_and_write(repo, key, current, expected, value, token) do
    if expected_value?(current, expected) do
      put_value(repo, key, value, token)
    else
      {:error, {__MODULE__, :conflict, token}}
    end
  end

  defp put_value(repo, key, value, token) do
    case repo.put(key, value) do
      :ok -> {:ok, {__MODULE__, :written, token}}
      result -> {:error, {__MODULE__, :operation_failed, token, :put, result}}
    end
  end

  defp clear_value(repo, key, token) do
    case repo.clear(key) do
      :ok -> {:ok, {__MODULE__, :written, token}}
      result -> {:error, {__MODULE__, :operation_failed, token, :clear, result}}
    end
  end

  defp expected_value?(nil, :not_found), do: true

  defp expected_value?(current, expected) when is_binary(current) and is_binary(expected),
    do: current === expected

  defp expected_value?(_current, _expected), do: false

  defp write(repo, opts, fun) do
    token = make_ref()

    result =
      isolated_transaction(repo, write_transaction_options(opts), fn -> fun.(repo, token) end)

    case result do
      {:return, {:ok, {__MODULE__, :written, ^token}}} -> :ok
      other -> indeterminate(other)
    end
  end

  defp isolated_transaction(repo, transaction_opts, fun) do
    caller = self()
    result_ref = make_ref()

    {worker, monitor} =
      spawn_monitor(fn ->
        watchdog = parent_watchdog(caller, self())
        result = capture_transaction(repo, transaction_opts, fun)
        send(watchdog, {:transaction_complete, result_ref})
        send(caller, {result_ref, result})
      end)

    receive do
      {^result_ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^worker, reason} ->
        {:fault, :exit, reason}
    end
  end

  defp parent_watchdog(caller, worker) do
    spawn_link(fn ->
      caller_monitor = Process.monitor(caller)

      receive do
        {:transaction_complete, _result_ref} ->
          Process.demonitor(caller_monitor, [:flush])
          :ok

        {:DOWN, ^caller_monitor, :process, ^caller, _reason} ->
          Process.exit(worker, :kill)
      end
    end)
  end

  defp capture_transaction(repo, transaction_opts, fun) do
    {:return, repo.transact(fun, transaction_opts)}
  rescue
    error -> {:fault, :error, error}
  catch
    kind, reason -> {:fault, kind, reason}
  end

  defp indeterminate({:return, {:error, reason}}),
    do: {:error, {:indeterminate, {:bedrock_transaction_failed, reason}}}

  defp indeterminate({:return, returned}),
    do: {:error, {:indeterminate, {:invalid_bedrock_result, returned}}}

  defp indeterminate({:fault, kind, reason}),
    do: {:error, {:indeterminate, {:bedrock_transaction_failed, kind, reason}}}

  defp storage_key(key, opts) do
    storage_key = Keyword.get(opts, :prefix, @default_prefix) <> key

    cond do
      byte_size(storage_key) > @max_key_bytes ->
        {:error, {:rejected, {:bedrock_key_too_large, byte_size(storage_key), @max_key_bytes}}}

      storage_key >= <<0xFF>> ->
        {:error, {:rejected, :bedrock_system_key_not_allowed}}

      true ->
        {:ok, storage_key}
    end
  end

  defp validate_value_size(value) when byte_size(value) <= @max_value_bytes, do: :ok

  defp validate_value_size(value),
    do: {:error, {:rejected, {:bedrock_value_too_large, byte_size(value), @max_value_bytes}}}

  defp repo(opts), do: Keyword.fetch!(opts, :repo)

  defp read_transaction_options(opts) do
    [timeout_in_ms: Keyword.get(opts, :timeout_in_ms, @default_timeout_in_ms)]
  end

  defp write_transaction_options(opts) do
    [
      retry_limit: 0,
      timeout_in_ms: Keyword.get(opts, :timeout_in_ms, @default_timeout_in_ms)
    ]
  end

  defp validate_options!(opts) do
    case validate_options(opts) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "Jido.Persistence.Bedrock #{reason}"
    end
  end

  defp validate_keyword_options(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, "options must be a keyword list"}
  end

  defp validate_duplicate_options(opts) do
    case duplicate_option(opts) do
      nil -> :ok
      option -> {:error, "option #{inspect(option)} is present more than once"}
    end
  end

  defp validate_known_options(opts) do
    case unknown_option(opts) do
      nil -> :ok
      option -> {:error, "unknown option #{inspect(option)}"}
    end
  end

  defp validate_dependencies do
    cond do
      not Code.ensure_loaded?(Bedrock.Repo) ->
        {:error, "requires the optional bedrock dependency at version 0.7.2 or later 0.7.x"}

      error = dependency_version_error() ->
        {:error, error}

      true ->
        :ok
    end
  end

  defp validate_repo_option(opts) do
    repo = Keyword.get(opts, :repo)

    cond do
      is_nil(repo) or not is_atom(repo) ->
        {:error, "requires a :repo module created with use Bedrock.Repo"}

      not valid_repo?(repo) ->
        {:error, ":repo must be a loaded module created with use Bedrock.Repo"}

      true ->
        :ok
    end
  end

  defp validate_prefix_option(opts) do
    if valid_prefix?(Keyword.get(opts, :prefix, @default_prefix)) do
      :ok
    else
      {:error, ":prefix must be a non-empty binary in the Bedrock user keyspace"}
    end
  end

  defp validate_timeout_option(opts) do
    if valid_timeout?(Keyword.get(opts, :timeout_in_ms, @default_timeout_in_ms)) do
      :ok
    else
      {:error, ":timeout_in_ms must be a positive integer or :infinity"}
    end
  end

  defp valid_repo?(repo) do
    Code.ensure_loaded?(repo) and
      Enum.all?(@repo_functions, fn {function, arity} ->
        function_exported?(repo, function, arity)
      end)
  end

  defp valid_prefix?(prefix) do
    is_binary(prefix) and prefix != "" and prefix < <<0xFF>>
  end

  defp valid_timeout?(:infinity), do: true
  defp valid_timeout?(timeout), do: is_integer(timeout) and timeout > 0

  defp dependency_version_error do
    [
      bedrock: @bedrock_version_requirement,
      bedrock_raft: @bedrock_raft_version_requirement
    ]
    |> Enum.find_value(fn {application, requirement} ->
      dependency_version_error(application, requirement)
    end)
  end

  defp dependency_version_error(application, requirement) do
    case Application.spec(application, :vsn) do
      nil ->
        "requires the #{application} application at #{requirement}"

      version ->
        validate_dependency_version(application, to_string(version), requirement)
    end
  end

  defp validate_dependency_version(application, version, requirement) do
    if Version.match?(version, requirement) do
      nil
    else
      "requires #{application} #{requirement}, but #{version} is loaded"
    end
  end

  defp duplicate_option(opts) do
    keys = Keyword.keys(opts)
    Enum.find(keys, fn key -> Enum.count(keys, &(&1 == key)) > 1 end)
  end

  defp unknown_option(opts) do
    opts
    |> Keyword.keys()
    |> Enum.find(&(&1 not in @option_keys))
  end
end
