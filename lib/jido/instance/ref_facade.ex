defmodule Jido.Instance.RefFacade do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Ref
  alias Jido.AgentServer
  alias Jido.Error

  @doc false
  @spec build_ref(atom(), String.t(), keyword()) ::
          {:ok, Ref.t()} | {:error, Error.ValidationError.t()}
  def build_ref(instance, id, opts)

  def build_ref(instance, id, opts) when is_atom(instance) and is_binary(id) do
    with :ok <- validate_keyword(opts),
         :ok <- validate_ref_keys(opts),
         {:ok, namespace} <- require_namespace(instance) do
      Ref.new(namespace: namespace, partition: Keyword.get(opts, :partition), id: id)
    end
  end

  def build_ref(_instance, id, _opts),
    do: invalid("Agent Ref ID must be a binary", %{id: id})

  @doc false
  @spec resolve(atom(), Ref.t()) :: {:ok, pid()} | {:error, term()}
  def resolve(instance, %Ref{} = ref) do
    resolve_target(instance, ref)
  end

  defp resolve_target(instance, ref) do
    with {:ok, ref} <- Ref.validate(ref),
         :ok <- require_matching_namespace(instance, ref.namespace) do
      key = AgentServer.RegistrationGuard.registry_key(ref.id, ref.partition)

      case Registry.lookup(Jido.registry_name(instance), key) do
        [{pid, status}] ->
          runtime_target(pid, status)

        _ ->
          {:error, :not_found}
      end
    end
  rescue
    ArgumentError -> {:error, :unavailable}
  end

  defp runtime_target(pid, status) do
    case {status, :proc_lib.translate_initial_call(pid)} do
      {:ready, {AgentServer, :init, 1}} ->
        {:ok, pid}

      {:starting, {AgentServer, :init, 1}} ->
        {:error, :recovering}

      _ ->
        {:error, :not_found}
    end
  end

  @doc false
  def start_agent(instance, %Ref{} = ref, agent, opts) do
    with {:ok, ref} <- Ref.validate(ref),
         :ok <- require_matching_namespace(instance, ref.namespace),
         {:ok, opts} <- ref_options(ref, opts) do
      Jido.start_agent(instance, agent, opts)
    end
  end

  @doc false
  def activate_agent(instance, %Ref{} = ref, agent_module, opts) do
    with {:ok, ref} <- Ref.validate(ref),
         :ok <- require_matching_namespace(instance, ref.namespace),
         {:ok, opts} <- ref_options(ref, opts) do
      Jido.thaw(instance, agent_module, ref.id, opts)
    end
  end

  @doc false
  def call(instance, %Ref{} = ref, signal, timeout_or_opts) do
    with_server(instance, ref, :call, [signal, timeout_or_opts])
  end

  @doc false
  def cast(instance, %Ref{} = ref, signal) do
    with_server(instance, ref, :cast, [signal])
  end

  @doc false
  def submit(instance, %Ref{} = ref, signal, opts \\ []) do
    with_server(instance, ref, :submit, [signal, opts])
  end

  @doc false
  def stop(instance, %Ref{} = ref, reason, timeout) do
    with_server(instance, ref, :stop, [reason, timeout])
  end

  @doc false
  def hibernate(instance, %Ref{} = ref, opts) do
    with_server(instance, ref, :hibernate, [opts])
  end

  @doc false
  def delete(instance, %Ref{} = ref, agent_module, opts) do
    with {:ok, ref} <- Ref.validate(ref),
         :ok <- require_matching_namespace(instance, ref.namespace),
         :ok <- validate_keyword(opts),
         {:error, :not_found} <- resolve(instance, ref) do
      source = Keyword.get(opts, :persistence, instance)

      persistence_opts =
        opts
        |> Keyword.delete(:persistence)
        |> Keyword.put(:instance, instance)
        |> Keyword.put(:namespace, ref.namespace)
        |> Keyword.put(:partition, ref.partition)

      Jido.Persistence.delete_agent(source, agent_module, ref.id, persistence_opts)
    else
      {:ok, _pid} -> {:error, :agent_running}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  def cancel(instance, %Ref{} = ref, timeout) do
    with_server(instance, ref, :cancel, [timeout])
  end

  @doc false
  def cancel_turn(instance, %Ref{} = ref, turn_id, timeout) do
    with_server(instance, ref, :cancel_turn, [turn_id, timeout])
  end

  @doc false
  def attach(instance, %Ref{} = ref, owner_pid, timeout) do
    with_server(instance, ref, :attach, [owner_pid, timeout])
  end

  @doc false
  def detach(instance, %Ref{} = ref, owner_pid, timeout) do
    with_server(instance, ref, :detach, [owner_pid, timeout])
  end

  @doc false
  def touch(instance, %Ref{} = ref) do
    with_server(instance, ref, :touch, [])
  end

  @doc false
  def agent(instance, %Ref{} = ref, timeout) do
    with_server(instance, ref, :agent, [timeout])
  end

  @doc false
  def plugin_state(instance, %Ref{} = ref, plugin, timeout) do
    with_server(instance, ref, :plugin_state, [plugin, timeout])
  end

  @doc false
  def status(instance, %Ref{} = ref, timeout) do
    with_server(instance, ref, :status, [timeout])
  end

  @doc false
  def children(instance, %Ref{} = ref, timeout) do
    with_server(instance, ref, :children, [timeout])
  end

  @doc false
  def await_ready(instance, %Ref{} = ref, timeout) do
    with_server(instance, ref, :await_ready, [timeout])
  end

  defp with_server(instance, ref, operation, args) do
    with {:ok, pid} <- resolve_target(instance, ref) do
      invoke(AgentServer, operation, [pid | args])
    end
  end

  defp invoke(runtime, operation, args) do
    apply(runtime, operation, args)
  catch
    :exit, reason ->
      if not match?({:timeout, _}, reason),
        do: {:error, :unavailable},
        else: exit(reason)
  end

  defp ref_options(%Ref{} = ref, opts) do
    with :ok <- validate_keyword(opts),
         :ok <- matching_option(opts, :id, ref.id),
         :ok <- matching_option(opts, :partition, ref.partition) do
      {:ok,
       opts
       |> Keyword.put(:id, ref.id)
       |> Keyword.put(:partition, ref.partition)}
    end
  end

  defp matching_option(opts, key, expected) do
    case Keyword.fetch(opts, key) do
      :error ->
        :ok

      {:ok, ^expected} ->
        :ok

      {:ok, value} ->
        invalid("Agent Ref conflicts with startup options", %{key: key, value: value})
    end
  end

  defp require_matching_namespace(instance, namespace) do
    with {:ok, bound} <- require_namespace(instance) do
      if bound == namespace do
        :ok
      else
        invalid("Agent Ref namespace does not match the Jido instance", %{
          code: :jido_namespace_mismatch,
          expected: bound,
          actual: namespace
        })
      end
    end
  end

  defp require_namespace(instance) do
    case Jido.namespace(instance) do
      namespace when is_binary(namespace) ->
        {:ok, namespace}

      nil ->
        invalid("Jido instance does not have a stable namespace", %{
          code: :jido_namespace_required,
          instance: instance
        })
    end
  end

  defp validate_keyword(opts) do
    if Keyword.keyword?(opts) do
      keys = Keyword.keys(opts)

      case keys -- Enum.uniq(keys) do
        [] ->
          :ok

        duplicates ->
          invalid("Ref facade options must contain unique keys", %{
            keys: Enum.uniq(duplicates)
          })
      end
    else
      invalid("Ref facade options must be a keyword list", %{value: opts})
    end
  end

  defp validate_ref_keys(opts) do
    case Enum.reject(Keyword.keys(opts), &(&1 == :partition)) do
      [] -> :ok
      keys -> invalid("Agent Ref options have unknown keys", %{keys: keys})
    end
  end

  defp invalid(message, details) do
    {:error,
     Error.validation_error(message,
       kind: :input,
       subject: Agent,
       details: Map.put_new(details, :code, :jido_instance_invalid_config)
     )}
  end
end
