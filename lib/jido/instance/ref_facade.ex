defmodule Jido.Instance.RefFacade do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Ref
  alias Jido.AgentServer
  alias Jido.Error

  @default_timeout 5_000

  @doc false
  @spec build_ref(atom(), String.t(), keyword()) ::
          {:ok, Ref.t()} | {:error, Error.ValidationError.t()}
  def build_ref(instance, id, opts \\ [])

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
  def resolve(instance, %Ref{} = ref) when is_atom(instance) do
    with {:ok, ref} <- Ref.validate(ref),
         :ok <- require_matching_namespace(instance, ref.namespace) do
      case Jido.whereis_agent(instance, ref.id, partition: ref.partition) do
        pid when is_pid(pid) -> {:ok, pid}
        nil -> {:error, :not_found}
      end
    end
  end

  @doc false
  def start_agent(instance, %Ref{} = ref, agent, opts \\ []) when is_atom(instance) do
    with {:ok, ref} <- Ref.validate(ref),
         :ok <- require_matching_namespace(instance, ref.namespace),
         {:ok, opts} <- ref_options(ref, opts) do
      Jido.start_agent(instance, agent, opts)
    end
  end

  @doc false
  def activate_agent(instance, %Ref{} = ref, agent_module, opts \\ [])
      when is_atom(instance) and is_atom(agent_module) do
    with {:ok, ref} <- Ref.validate(ref),
         :ok <- require_matching_namespace(instance, ref.namespace),
         {:ok, opts} <- ref_options(ref, opts) do
      Jido.thaw(instance, agent_module, ref.id, opts)
    end
  end

  @doc false
  def call(instance, %Ref{} = ref, signal, timeout_or_opts \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.call(&1, signal, timeout_or_opts))
  end

  @doc false
  def cast(instance, %Ref{} = ref, signal) do
    with_server(instance, ref, &AgentServer.cast(&1, signal))
  end

  @doc false
  def send_request(instance, %Ref{} = ref, signal, timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.send_request(&1, signal, timeout))
  end

  @doc false
  def stop(instance, %Ref{} = ref, reason \\ :shutdown, timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.stop(&1, reason, timeout))
  end

  @doc false
  def hibernate(instance, %Ref{} = ref, opts \\ []) do
    with_server(instance, ref, &AgentServer.hibernate(&1, opts))
  end

  @doc false
  def delete(instance, %Ref{} = ref, agent_module, opts \\ [])
      when is_atom(instance) and is_atom(agent_module) do
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
  def cancel(instance, %Ref{} = ref, timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.cancel(&1, timeout))
  end

  @doc false
  def cancel_turn(instance, %Ref{} = ref, turn_id, timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.cancel_turn(&1, turn_id, timeout))
  end

  @doc false
  def attach(instance, %Ref{} = ref, owner_pid \\ self(), timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.attach(&1, owner_pid, timeout))
  end

  @doc false
  def detach(instance, %Ref{} = ref, owner_pid \\ self(), timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.detach(&1, owner_pid, timeout))
  end

  @doc false
  def touch(instance, %Ref{} = ref) do
    with_server(instance, ref, &AgentServer.touch/1)
  end

  @doc false
  def agent(instance, %Ref{} = ref, timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.agent(&1, timeout))
  end

  @doc false
  def plugin_state(instance, %Ref{} = ref, plugin, timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.plugin_state(&1, plugin, timeout))
  end

  @doc false
  def status(instance, %Ref{} = ref, timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.status(&1, timeout))
  end

  @doc false
  def snapshot(instance, %Ref{} = ref, timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.snapshot(&1, timeout))
  end

  @doc false
  def children(instance, %Ref{} = ref, timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.children(&1, timeout))
  end

  @doc false
  def await_ready(instance, %Ref{} = ref, timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.await_ready(&1, timeout))
  end

  @doc false
  def set_debug(instance, %Ref{} = ref, enabled, timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.set_debug(&1, enabled, timeout))
  end

  @doc false
  def recent_events(instance, %Ref{} = ref, opts \\ [], timeout \\ @default_timeout) do
    with_server(instance, ref, &AgentServer.recent_events(&1, opts, timeout))
  end

  defp with_server(instance, ref, operation) do
    with {:ok, pid} <- resolve(instance, ref), do: operation.(pid)
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
    if Keyword.keyword?(opts),
      do: :ok,
      else: invalid("Ref facade options must be a keyword list", %{value: opts})
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
