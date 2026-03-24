defmodule Jido.Pod do
  @moduledoc """
  Pod wrapper macro and runtime helpers.

  A pod is just a `Jido.Agent` with a canonical topology and a singleton pod
  plugin mounted under the reserved `:__pod__` state key.
  """

  alias Jido.Agent
  alias Jido.Agent.DefaultPlugins
  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.AgentServer.ChildInfo
  alias Jido.AgentServer.State
  alias Jido.Plugin.Instance, as: PluginInstance
  alias Jido.Pod.Plugin
  alias Jido.Pod.Topology
  alias Jido.Pod.Topology.Node

  @pod_state_key Plugin.state_key_atom()
  @pod_capability Plugin.capability()

  @type node_snapshot :: %{
          node: Node.t(),
          key: term(),
          pid: pid() | nil,
          running_pid: pid() | nil,
          adopted_pid: pid() | nil,
          adopted?: boolean(),
          status: :adopted | :running | :stopped
        }

  @doc false
  def expand_aliases_in_ast(ast, caller_env) do
    Macro.prewalk(ast, fn
      {:__aliases__, _, _} = alias_node -> Macro.expand(alias_node, caller_env)
      other -> other
    end)
  end

  @doc false
  def expand_and_eval_literal_option(value, caller_env) do
    case value do
      nil ->
        nil

      value when is_atom(value) or is_binary(value) or is_number(value) or is_map(value) ->
        value

      value when is_list(value) ->
        value
        |> expand_aliases_in_ast(caller_env)
        |> Code.eval_quoted([], caller_env)
        |> elem(0)

      value when is_tuple(value) ->
        value
        |> expand_aliases_in_ast(caller_env)
        |> Code.eval_quoted([], caller_env)
        |> elem(0)

      other ->
        other
    end
  end

  @doc false
  def resolve_topology!(name, raw_topology, caller_env) do
    resolved = expand_and_eval_literal_option(raw_topology, caller_env)

    case resolved do
      %Topology{} = topology ->
        case Topology.with_name(topology, name) do
          {:ok, updated} ->
            updated

          {:error, reason} ->
            raise CompileError,
              description: inspect(reason),
              file: caller_env.file,
              line: caller_env.line
        end

      topology when is_map(topology) ->
        Topology.from_nodes!(name, topology)

      other ->
        raise CompileError,
          description:
            "Invalid Jido.Pod topology for #{inspect(caller_env.module)}: expected a map or %Jido.Pod.Topology{}, got: #{inspect(other)}",
          file: caller_env.file,
          line: caller_env.line
    end
  end

  @doc false
  def split_pod_plugins!(default_plugins, caller_env) do
    pod_override =
      if is_map(default_plugins) do
        Map.take(default_plugins, [@pod_state_key])
      else
        %{}
      end

    pod_plugins = DefaultPlugins.apply_agent_overrides([Plugin], pod_override)

    if pod_plugins == [] do
      raise CompileError,
        description:
          "Jido.Pod requires a singleton pod plugin under #{@pod_state_key}. " <>
            "Replace it with `default_plugins: %{#{@pod_state_key}: YourPlugin}` instead of disabling it.",
        file: caller_env.file,
        line: caller_env.line
    end

    Enum.each(pod_plugins, &validate_pod_plugin_decl!(&1, caller_env))

    remaining_default_plugins =
      if is_map(default_plugins) do
        Map.delete(default_plugins, @pod_state_key)
      else
        default_plugins
      end

    {pod_plugins, remaining_default_plugins}
  end

  defp validate_pod_plugin_decl!(decl, caller_env) do
    mod =
      case decl do
        {module, _config} -> module
        module -> module
      end

    case Code.ensure_compiled(mod) do
      {:module, _compiled} ->
        :ok

      {:error, reason} ->
        raise CompileError,
          description: "Pod plugin #{inspect(mod)} could not be compiled: #{inspect(reason)}",
          file: caller_env.file,
          line: caller_env.line
    end

    instance =
      try do
        PluginInstance.new(decl)
      rescue
        error in [ArgumentError] ->
          raise CompileError,
            description: "Invalid pod plugin #{inspect(mod)}: #{Exception.message(error)}",
            file: caller_env.file,
            line: caller_env.line
      end

    cond do
      not instance.manifest.singleton ->
        raise CompileError,
          description: "#{inspect(mod)} must be a singleton plugin to replace the pod plugin.",
          file: caller_env.file,
          line: caller_env.line

      instance.state_key != @pod_state_key ->
        raise CompileError,
          description:
            "#{inspect(mod)} must use state_key #{@pod_state_key} to replace the pod plugin.",
          file: caller_env.file,
          line: caller_env.line

      @pod_capability not in (instance.manifest.capabilities || []) ->
        raise CompileError,
          description:
            "#{inspect(mod)} must advertise capability #{@pod_capability} to replace the pod plugin.",
          file: caller_env.file,
          line: caller_env.line

      true ->
        :ok
    end
  end

  defmacro __using__(opts) do
    name = __MODULE__.expand_and_eval_literal_option(Keyword.fetch!(opts, :name), __CALLER__)
    raw_topology = Keyword.fetch!(opts, :topology)
    topology = __MODULE__.resolve_topology!(name, raw_topology, __CALLER__)

    default_plugins =
      __MODULE__.expand_and_eval_literal_option(Keyword.get(opts, :default_plugins), __CALLER__)

    {pod_plugins, remaining_default_plugins} =
      __MODULE__.split_pod_plugins!(default_plugins, __CALLER__)

    agent_opts =
      opts
      |> Keyword.delete(:topology)
      |> Keyword.put(:plugins, pod_plugins ++ Keyword.get(opts, :plugins, []))
      |> then(fn resolved_opts ->
        if is_nil(remaining_default_plugins) do
          Keyword.delete(resolved_opts, :default_plugins)
        else
          Keyword.put(resolved_opts, :default_plugins, remaining_default_plugins)
        end
      end)

    quote location: :keep do
      use Jido.Agent, unquote(Macro.escape(agent_opts))

      @pod_topology unquote(Macro.escape(topology))

      @doc "Returns the canonical topology for this pod agent."
      @spec topology() :: Jido.Pod.Topology.t()
      def topology, do: @pod_topology

      @doc "Returns true for pod-wrapped agent modules."
      @spec pod?() :: true
      def pod?, do: true
    end
  end

  @doc """
  Returns the reserved pod plugin instance for a pod-wrapped agent module.
  """
  @spec pod_plugin_instance(module()) :: {:ok, PluginInstance.t()} | {:error, term()}
  def pod_plugin_instance(agent_module) when is_atom(agent_module) do
    instances =
      if function_exported?(agent_module, :plugin_instances, 0) do
        agent_module.plugin_instances()
      else
        []
      end

    case Enum.find(instances, &(&1.state_key == @pod_state_key)) do
      %PluginInstance{} = instance ->
        {:ok, instance}

      nil ->
        {:error,
         Jido.Error.validation_error(
           "#{inspect(agent_module)} is missing the reserved #{@pod_state_key} plugin instance."
         )}
    end
  end

  @doc """
  Fetches pod plugin state from an agent or server state.
  """
  @spec fetch_state(Agent.t() | State.t()) :: {:ok, map()} | {:error, term()}
  def fetch_state(%State{agent: agent}), do: fetch_state(agent)

  def fetch_state(%Agent{agent_module: agent_module, state: state}) when is_map(state) do
    with {:ok, instance} <- pod_plugin_instance(agent_module) do
      case Map.get(state, instance.state_key) do
        plugin_state when is_map(plugin_state) ->
          {:ok, plugin_state}

        other ->
          {:error,
           Jido.Error.validation_error(
             "Pod plugin state is missing or malformed.",
             details: %{state_key: instance.state_key, value: other}
           )}
      end
    end
  end

  def fetch_state(agent) do
    {:error,
     Jido.Error.validation_error(
       "Expected an agent or AgentServer state when fetching pod state.",
       details: %{agent: agent}
     )}
  end

  @doc """
  Fetches the canonical topology from a module, agent, or running pod server.
  """
  @spec fetch_topology(module() | Agent.t() | State.t() | AgentServer.server()) ::
          {:ok, Topology.t()} | {:error, term()}
  def fetch_topology(module) when is_atom(module) do
    if function_exported?(module, :topology, 0) do
      {:ok, module.topology()}
    else
      with {:ok, state} <- AgentServer.state(module) do
        fetch_topology(state)
      end
    end
  end

  def fetch_topology(%State{agent: agent}), do: fetch_topology(agent)

  def fetch_topology(%Agent{} = agent) do
    with {:ok, plugin_state} <- fetch_state(agent) do
      extract_topology(plugin_state)
    end
  end

  def fetch_topology(server) do
    with {:ok, state} <- AgentServer.state(server) do
      fetch_topology(state)
    end
  end

  @doc """
  Replaces the persisted topology snapshot in a pod agent.
  """
  @spec put_topology(Agent.t(), Topology.t()) :: {:ok, Agent.t()} | {:error, term()}
  def put_topology(%Agent{} = agent, %Topology{} = topology) do
    with {:ok, instance} <- pod_plugin_instance(agent.agent_module),
         {:ok, pod_state} <- fetch_state(agent) do
      updated_state =
        pod_state
        |> Map.put(:topology, topology)
        |> Map.put(:topology_version, topology.version)

      {:ok, %{agent | state: Map.put(agent.state, instance.state_key, updated_state)}}
    end
  end

  @doc """
  Applies a pure topology transformation to a pod agent.
  """
  @spec update_topology(
          Agent.t(),
          (Topology.t() -> Topology.t() | {:ok, Topology.t()} | {:error, term()})
        ) ::
          {:ok, Agent.t()} | {:error, term()}
  def update_topology(%Agent{} = agent, fun) when is_function(fun, 1) do
    with {:ok, topology} <- fetch_topology(agent),
         {:ok, new_topology} <- normalize_topology_update(fun.(topology)) do
      put_topology(agent, new_topology)
    end
  end

  @doc """
  Returns runtime snapshots for every node in a running pod.
  """
  @spec nodes(AgentServer.server()) :: {:ok, %{atom() => node_snapshot()}} | {:error, term()}
  def nodes(server) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- fetch_topology(state) do
      {:ok, build_node_snapshots(state, topology)}
    end
  end

  @doc """
  Looks up a node's live process if it is currently running.
  """
  @spec lookup_node(AgentServer.server(), atom()) :: {:ok, pid()} | :error | {:error, term()}
  def lookup_node(server, name) when is_atom(name) do
    with {:ok, snapshots} <- nodes(server) do
      case Map.get(snapshots, name) do
        nil -> {:error, :unknown_node}
        %{pid: pid} when is_pid(pid) -> {:ok, pid}
        _snapshot -> :error
      end
    end
  end

  @doc """
  Ensures a named node is running and adopted into the pod manager.
  """
  @spec ensure_node(AgentServer.server(), atom(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_node(server, name, opts \\ []) when is_atom(name) and is_list(opts) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- fetch_topology(state),
         {:ok, node} <- fetch_node(topology, name) do
      case Map.get(state.children, name) do
        %ChildInfo{pid: pid} when is_pid(pid) ->
          if Process.alive?(pid) do
            {:ok, pid}
          else
            ensure_node_from_manager(server, state, node, name, opts)
          end

        _child_info ->
          ensure_node_from_manager(server, state, node, name, opts)
      end
    end
  end

  @doc """
  Ensures all eager nodes are running and adopted into the pod manager.
  """
  @spec reconcile(AgentServer.server(), keyword()) :: {:ok, %{atom() => pid()}} | {:error, term()}
  def reconcile(server, opts \\ []) when is_list(opts) do
    with {:ok, topology} <- fetch_topology(server) do
      eager_nodes =
        topology.nodes
        |> Enum.filter(fn {_name, node} -> node.activation == :eager end)

      Enum.reduce_while(eager_nodes, {:ok, %{}}, fn {name, _node}, {:ok, acc} ->
        case ensure_node(server, name, opts) do
          {:ok, pid} ->
            {:cont, {:ok, Map.put(acc, name, pid)}}

          {:error, reason} ->
            {:halt, {:error, %{node: name, reason: reason}}}
        end
      end)
    end
  end

  defp extract_topology(%{topology: %Topology{} = topology}), do: {:ok, topology}

  defp extract_topology(plugin_state) do
    {:error,
     Jido.Error.validation_error(
       "Pod plugin state does not contain a valid topology snapshot.",
       details: %{state: plugin_state}
     )}
  end

  defp normalize_topology_update({:ok, %Topology{} = topology}), do: {:ok, topology}
  defp normalize_topology_update(%Topology{} = topology), do: {:ok, topology}
  defp normalize_topology_update({:error, _reason} = error), do: error

  defp normalize_topology_update(other) do
    {:error,
     Jido.Error.validation_error(
       "Topology update function must return a Jido.Pod.Topology or {:ok, topology}.",
       details: %{result: other}
     )}
  end

  defp fetch_node(%Topology{} = topology, name) when is_atom(name) do
    case Topology.fetch_node(topology, name) do
      {:ok, %Node{} = node} ->
        {:ok, node}

      :error ->
        {:error, :unknown_node}
    end
  end

  defp build_node_snapshots(%State{} = state, %Topology{} = topology) do
    Map.new(topology.nodes, fn {name, node} ->
      key = node_key(state, name)
      adopted_pid = adopted_child_pid(state, name)
      running_pid = running_child_pid(node.manager, key)

      snapshot = %{
        node: node,
        key: key,
        pid: adopted_pid || running_pid,
        running_pid: running_pid,
        adopted_pid: adopted_pid,
        adopted?: is_pid(adopted_pid),
        status: snapshot_status(adopted_pid, running_pid)
      }

      {name, snapshot}
    end)
  end

  defp adopted_child_pid(%State{} = state, name) do
    case Map.get(state.children, name) do
      %ChildInfo{pid: pid} when is_pid(pid) ->
        if Process.alive?(pid), do: pid, else: nil

      _ ->
        nil
    end
  end

  defp ensure_node_from_manager(server, state, node, name, opts) do
    initial_state = Keyword.get(opts, :initial_state, node.initial_state)
    key = node_key(state, name)

    with {:ok, pid} <- get_managed_node(node.manager, key, initial_state: initial_state),
         {:ok, ^pid} <- AgentServer.adopt_child(server, pid, name, node.meta) do
      {:ok, pid}
    end
  end

  defp running_child_pid(manager, key) do
    try do
      case InstanceManager.lookup(manager, key) do
        {:ok, pid} -> pid
        :error -> nil
      end
    rescue
      ArgumentError -> nil
    end
  end

  defp get_managed_node(manager, key, opts) do
    try do
      InstanceManager.get(manager, key, opts)
    rescue
      error in [ArgumentError, KeyError] ->
        {:error,
         Jido.Error.validation_error(
           "Failed to acquire pod node from InstanceManager.",
           details: %{manager: manager, key: key, error: Exception.message(error)}
         )}
    end
  end

  defp snapshot_status(adopted_pid, _running_pid) when is_pid(adopted_pid), do: :adopted
  defp snapshot_status(nil, running_pid) when is_pid(running_pid), do: :running
  defp snapshot_status(_adopted_pid, _running_pid), do: :stopped

  defp node_key(%State{} = state, name) do
    {state.agent_module, pod_key(state), name}
  end

  defp pod_key(%State{lifecycle: %{pool_key: pool_key}}) when not is_nil(pool_key), do: pool_key
  defp pod_key(%State{id: id}), do: id
end
