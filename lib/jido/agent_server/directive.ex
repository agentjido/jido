defmodule Jido.AgentServer.Directive do
  @moduledoc """
  Runtime requests. AgentServer runs them after it commits the Agent value.

  Topology edits belong to `Jido.Agent.Directive`. These records request
  runtime work after commit. Activation ownership is fixed at startup.
  """
  alias Jido.Agent.Directive.Emit
  alias Jido.AgentServer.Directive.AgentSend
  alias Jido.AgentServer.Directive.OwnerSend
  alias Jido.AgentServer.Directive.ErrorReport
  alias Jido.AgentServer.Directive.AgentStart
  alias Jido.AgentServer.Directive.ProcessStart
  alias Jido.AgentServer.Directive.ServerStop
  alias Jido.AgentServer.Directive.AgentStop

  @restart_policies [:permanent, :temporary, :transient]
  @unsupported_agent_start_opts [
    :agent,
    :jido,
    :partition,
    :runner,
    :node,
    :lifecycle_mod,
    :pool,
    :pool_key,
    :idle_timeout,
    :persistence,
    :restore,
    :state_version
  ]

  def signal_send(signal, pid, opts \\ []) when is_pid(pid),
    do: %Emit{
      signal: signal,
      dispatch:
        {:pid,
         Keyword.put(options(opts, [:delivery_mode, :timeout, :message_format]), :target, pid)}
    }

  def owner_send(signal), do: %OwnerSend{signal: signal}
  def agent_send(name, signal), do: %AgentSend{name: name, signal: signal}
  def error_report(error, context \\ nil), do: %ErrorReport{error: error, context: context}
  def process_start(child_spec), do: %ProcessStart{child_spec: child_spec}

  def agent_start(agent, name, opts \\ []) do
    opts = options(opts, [:node, :opts, :meta, :restart])

    %AgentStart{
      agent: agent,
      name: name,
      node: Keyword.get(opts, :node),
      opts: option_map(opts, :opts),
      meta: option_map(opts, :meta),
      restart: Keyword.get(opts, :restart, :transient)
    }
  end

  def agent_stop(name, reason \\ :normal), do: %AgentStop{name: name, reason: reason}
  def server_stop(reason \\ :normal), do: %ServerStop{reason: reason}

  @doc false
  def validate_restart_policy(restart, _opts \\ [])
  def validate_restart_policy(restart, _opts) when restart in @restart_policies, do: :ok

  def validate_restart_policy(restart, _opts) do
    {:error, "restart must be one of #{inspect(@restart_policies)}, got: #{inspect(restart)}"}
  end

  @doc false
  def validate_agent_start_opts(opts, _refinement_opts \\ [])

  def validate_agent_start_opts(opts, _refinement_opts) when is_map(opts) do
    unsupported = Enum.filter(@unsupported_agent_start_opts, &Map.has_key?(opts, &1))

    case unsupported do
      [] -> :ok
      [:node] -> {:error, "Use AgentStart.node for placement, not opts.node"}
      keys -> {:error, "AgentStart does not support lifecycle options #{inspect(keys)}"}
    end
  end

  def validate_agent_start_opts(value, _refinement_opts),
    do: {:error, "AgentStart opts must be a map, got: #{inspect(value)}"}

  @doc false
  def validate_agent_target(%Jido.Agent{} = agent) do
    case Jido.Agent.validate(agent) do
      {:ok, _agent} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  def validate_agent_target(module) when is_atom(module) do
    with {:ok, _definition} <- Jido.Agent.Validation.resolve(module) do
      :ok
    else
      _reason -> {:error, {:invalid_agent_module, module}}
    end
  end

  def validate_agent_target(value), do: {:error, {:invalid_agent, value}}

  defp options(opts, allowed) do
    unless Keyword.keyword?(opts) and Enum.uniq(Keyword.keys(opts)) == Keyword.keys(opts),
      do: raise(ArgumentError, "Expected unique keyword options")

    Keyword.validate!(opts, allowed)
  end

  defp option_map(opts, key) do
    case Jido.Agent.Authoring.to_attrs(Keyword.get(opts, key, %{}), :reject) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "#{key} must be a plain Map or unique keyword list"
    end
  end
end
