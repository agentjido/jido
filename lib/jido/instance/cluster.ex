defmodule Jido.Instance.Cluster do
  @moduledoc false

  alias Jido.AgentServer.Status
  alias Jido.Instance.{Names, RuntimeStore}
  alias Jido.Persistence.{Config, Store}

  @max_timeout 4_294_967_295
  @default_timeout 5_000

  @spec configured?(term()) :: boolean()
  def configured?(opts) when is_list(opts) do
    Keyword.keyword?(opts) and Keyword.get(opts, :cluster, false) != false
  end

  def configured?(_opts), do: false

  def validate(false, _namespace, _persistence), do: {:ok, false}

  def validate(opts, namespace, persistence) do
    with true <- Keyword.keyword?(opts),
         keys = Keyword.keys(opts),
         true <- keys == Enum.uniq(keys) and keys -- [:home, :generation, :rpc_timeout] == [],
         true <- is_binary(namespace),
         true <- Node.alive?(),
         home when is_atom(home) and home not in [nil, false, true, :nonode@nohost] <- opts[:home],
         true <- valid_home?(home),
         generation = opts[:generation],
         true <- valid_generation?(generation, persistence),
         timeout when is_integer(timeout) and timeout in 1..@max_timeout <-
           Keyword.get(opts, :rpc_timeout, @default_timeout) do
      {:ok, %{home: home, generation: generation, rpc_timeout: timeout}}
    else
      _ ->
        {:error, Jido.Error.validation_error("Invalid Jido cluster configuration", kind: :config)}
    end
  end

  def ingress?(%{home: home}), do: home != node()
  def ingress?(_), do: false

  def ready?(instance, owner) do
    is_pid(owner) and Process.whereis(instance) == owner and RuntimeStore.wake_ready?(instance) and
      Enum.all?(
        [
          Names.agent_supervisor(instance),
          Names.registry(instance),
          Names.registration_guard(instance),
          Names.exec_runner(instance),
          Names.task_supervisor(instance),
          Names.runtime_store(instance)
        ],
        &is_pid(Process.whereis(&1))
      )
  end

  def require_home(instance) when is_atom(instance) do
    case RuntimeStore.instance_cluster(instance) do
      %{home: home} when home == node() ->
        :ok

      %{home: _home} ->
        {:error, :cluster_not_home}

      _ ->
        :ok
    end
  end

  def require_home(_instance), do: :ok

  def require_ready_home(instance) when is_atom(instance) do
    with :ok <- require_home(instance) do
      case RuntimeStore.instance_cluster(instance) do
        false ->
          :ok

        _cluster ->
          if ready?(instance, Process.whereis(instance)), do: :ok, else: {:error, :cluster_unavailable}
      end
    end
  end

  def require_ready_home(_instance), do: :ok

  def require_managed_activation(nil), do: :ok

  def require_managed_activation(instance) when is_atom(instance) do
    case RuntimeStore.instance_cluster(instance) do
      false ->
        :ok

      %{home: home} when home == node() ->
        supervisor = Process.whereis(Names.agent_supervisor(instance))
        ready? = ready?(instance, Process.whereis(instance))

        cond do
          not ready? ->
            {:error, :cluster_unavailable}

          not is_pid(supervisor) or
              not supervised_by?(self(), supervisor, Process.get(:"$ancestors", [])) ->
            {:error, :cluster_requires_managed_activation}

          true ->
            :ok
        end

      _ ->
        {:error, :cluster_not_home}
    end
  end

  def require_managed_activation(_invalid_instance), do: :ok

  defp supervised_by?(supervisor, supervisor, _ancestors), do: true

  defp supervised_by?(child, supervisor, [ancestor | rest]) do
    parent = if is_atom(ancestor), do: Process.whereis(ancestor), else: ancestor

    with true <- is_pid(parent),
         {:links, links} <- Process.info(child, :links),
         true <- parent in links do
      supervised_by?(parent, supervisor, rest)
    else
      _ -> false
    end
  end

  defp supervised_by?(_child, _supervisor, []), do: false

  def require_record(false, _config, _namespace), do: :ok
  def require_record(_cluster, nil, _namespace), do: :ok

  def require_record(%{home: home, generation: generation}, config, namespace) do
    expected = record({home, generation})

    case Store.read(config.store, key(namespace)) do
      {:ok, ^expected, _condition} -> :ok
      {:ok, _actual, _condition} -> {:error, :cluster_home_mismatch}
      {:error, :not_found} -> {:error, :cluster_home_not_provisioned}
      {:error, reason} -> {:error, {:cluster_home_unavailable, reason}}
    end
  end

  def change_home(profile, namespace, expected, {home, generation} = next)
      when is_binary(namespace) and byte_size(namespace) > 0 do
    with true <- valid_home?(home) and valid_generation?(generation, :required),
         {:ok, %Config{store: store}} <- Config.open(profile),
         {:ok, condition} <- home_condition(store, namespace, expected, next) do
      Store.compare_and_swap(store, key(namespace), condition, record(next))
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_cluster_home}
    end
  end

  def change_home(_profile, _namespace, _expected, _next), do: {:error, :invalid_cluster_home}

  def check_home(profile, namespace, {home, generation})
      when is_binary(namespace) and byte_size(namespace) > 0 do
    with true <- valid_home?(home) and valid_generation?(generation, :required),
         {:ok, %Config{} = config} <- Config.open(profile) do
      require_record(%{home: home, generation: generation}, config, namespace)
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_cluster_home}
    end
  end

  def check_home(_profile, _namespace, _expected), do: {:error, :invalid_cluster_home}

  defp home_condition(_store, _namespace, :not_found, _next), do: {:ok, :not_found}

  defp home_condition(store, namespace, {old_home, old_generation} = expected, {_new_home, new_generation})
       when is_binary(old_generation) and byte_size(old_generation) > 0 and old_generation != new_generation do
    if valid_home?(old_home) do
      bytes = record(expected)

      case Store.read(store, key(namespace)) do
        {:ok, ^bytes, condition} -> {:ok, condition}
        {:ok, _actual, _condition} -> {:error, :conflict}
        {:error, _reason} = error -> error
      end
    else
      {:error, :invalid_cluster_home}
    end
  end

  defp home_condition(_store, _namespace, _expected, _next), do: {:error, :invalid_cluster_home}

  defp record({home, generation}), do: :erlang.term_to_binary({:fixed_home_v1, Atom.to_string(home), generation})
  defp key(namespace), do: "jido:fixed-home:v1:" <> Base.url_encode64(namespace, padding: false)

  defp valid_home?(home) when is_atom(home) and home != :nonode@nohost,
    do: match?([name, host] when name != "" and host != "", String.split(Atom.to_string(home), "@"))

  defp valid_home?(_), do: false

  defp valid_generation?(nil, persistence) when persistence in [nil, false], do: true
  defp valid_generation?(value, _persistence), do: is_binary(value) and byte_size(value) > 0

  def remote(home, module, args, operation, timeout) do
    case :erpc.call(home, module, :__cluster_dispatch__, args, timeout) do
      {:jido_cluster_v1, result} -> result
      _unexpected -> transport_failure(operation, :invalid_reply)
    end
  catch
    :error, {:erpc, reason} ->
      transport_failure(operation, reason)

    :error, {:exception, :undef, [{^module, :__cluster_dispatch__, _, _} | _]} ->
      {:error, :cluster_unavailable}

    _kind, _reason ->
      transport_failure(operation, :remote_dispatch_failed)
  end

  def transport_failure(operation, reason) when operation in [:call, :cast],
    do: {:error, {:cluster_outcome_unknown, reason}}

  def transport_failure(_operation, _reason), do: {:error, :cluster_unavailable}

  def portable(value, error) do
    if Status.process_neutral?(value), do: :ok, else: {:error, error}
  end
end
