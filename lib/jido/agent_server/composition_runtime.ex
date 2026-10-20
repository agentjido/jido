defmodule Jido.AgentServer.CompositionRuntime do
  @moduledoc false

  alias Jido.Agent.{Mutation, Topology}
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.{Effects, Plugin, Supervisor, TopologyRuntime}

  @child_options ~w(placement on_parent_exit orphan_dispatch restart server_options meta)a

  def check(data, candidate, directives) do
    changed = Mutation.changed_plugins(data.agent, candidate, directives)

    if is_nil(data.activation) and requires_activation?(candidate, changed) do
      {:error, :activation_required}
    else
      with :ok <- validate_runtime(%{data | agent: candidate}),
           do: Plugin.validate_changes(data.plugin_specs, changed)
    end
  end

  def validate_runtime(data), do: TopologyRuntime.validate(data.agent)
  def reconcile(data), do: TopologyRuntime.reconcile(data)

  def spawn_child(server, agent, tag, opts) do
    token = make_ref()

    with {:ok, _agent} <- Jido.Agent.Validation.validate_instance(agent),
         {:ok, context, parent} <- child_options(server, tag, opts, token),
         :ok <- :gen_statem.call(server, {:reserve_child, tag, token}) do
      try do
        supervisor = child_supervisor(context, parent.placement)

        opts =
          context.opts
          |> Keyword.merge(Keyword.get(opts, :server_options, []))
          |> Keyword.put(:agent, agent)

        spec = %{
          Server.child_spec(opts)
          | start: Supervisor.start_spec(opts, parent),
            restart: parent.restart
        }

        case Supervisor.start_activation(supervisor, spec) do
          {:ok, worker} ->
            {:ok, worker}

          error ->
            Supervisor.release(context.state, tag, token)
            error
        end
      catch
        :exit, reason ->
          Supervisor.release(context.state, tag, token)
          {:error, {:child_start_failed, reason}}
      end
    end
  end

  def children(%{state: nil}), do: %{}

  def children(context) do
    Map.new(
      for {{:child, tag}, %{root: root} = record} <- Supervisor.records(context.state),
          worker = Supervisor.live_worker(root),
          is_pid(worker),
          do: {tag, %{pid: worker, activation: root, placement: record.placement}}
    )
  end

  def stop_child(server, tag, reason) do
    case Map.fetch(Server.children(server), tag) do
      {:ok, %{pid: worker, activation: root, placement: placement}} ->
        context = :gen_statem.call(server, :child_context)
        [{_, record}] = :ets.lookup(context.state, {:child, tag})

        result =
          if Map.get(record, :restart, :transient) == :permanent do
            context
            |> child_supervisor(placement)
            |> DynamicSupervisor.terminate_child(root)
          else
            Server.stop(worker, reason)
          end

        with :ok <- result,
             do: :gen_statem.call(server, {:forget_child, tag, root})

      :error ->
        {:error, :child_not_found}
    end
  end

  def adopt_child(server, child, tag, opts) do
    valid? = unique_options?(opts) and Keyword.get(opts, :placement, :independent) == :independent

    if valid? and Server.alive?(child) do
      token = make_ref()
      opts = Keyword.put(opts, :placement, :independent)

      with {:ok, context, parent} <- child_options(server, tag, opts, token) do
        lock = {{__MODULE__, :adoption, context.jido, context.partition}, self()}

        case :global.trans(
               lock,
               fn -> attach_child(server, child, tag, token, context, parent) end,
               [node()],
               0
             ) do
          :aborted -> {:error, :adoption_busy}
          result -> result
        end
      end
    else
      {:error, :invalid_child_options}
    end
  end

  defp requires_activation?(candidate, changed) do
    not Topology.empty?(candidate.topology) or
      TopologyRuntime.buses(candidate) != [] or changed != []
  end

  defp child_supervisor(context, :owned) do
    {:ok, supervisor} = Supervisor.child_supervisor(context.activation)
    supervisor
  end

  defp child_supervisor(context, :independent), do: Jido.agent_supervisor_name(context.jido)

  defp attach_child(server, child, tag, token, context, parent) do
    with :ok <- validate_adoption(context, child),
         :ok <- :gen_statem.call(server, {:reserve_child, tag, token}) do
      try do
        result = :gen_statem.call(child, {:attach_parent, parent})
        if result != :ok, do: Supervisor.release(context.state, tag, token)
        result
      catch
        :exit, _ ->
          Supervisor.release(context.state, tag, token)
          {:error, :child_unavailable}
      end
    end
  end

  defp validate_adoption(context, child) do
    root = Server.activation(child)

    cond do
      is_nil(root) ->
        {:error, :activation_required}

      root == context.activation ->
        {:error, :self_adoption}

      true ->
        case ancestor?(context.activation, root, []) do
          true -> {:error, :cyclic_parent}
          false -> :ok
          error -> error
        end
    end
  catch
    :exit, _ -> {:error, :child_unavailable}
  end

  @spec ancestor?(pid(), pid(), [pid()]) :: boolean() | {:error, atom()}
  defp ancestor?(root, root, _visited), do: true

  defp ancestor?(current, root, visited) do
    if current in visited do
      true
    else
      worker = Supervisor.worker(current)

      case :gen_statem.call(worker, :parent) do
        nil -> false
        parent -> ancestor?(parent.activation, root, [current | visited])
      end
    end
  catch
    :exit, _ -> {:error, :ancestor_unavailable}
  end

  defp child_options(server, tag, opts, token) do
    if unique_options?(opts) and Keyword.keys(opts) -- @child_options == [] do
      context = :gen_statem.call(server, :child_context)
      placement = Keyword.get(opts, :placement, :owned)
      policy = Keyword.get(opts, :on_parent_exit, :stop)
      dispatch = opts[:orphan_dispatch]

      cond do
        is_nil(context.activation) ->
          {:error, :activation_required}

        Server.Directive.validate_restart_policy(Keyword.get(opts, :restart, :transient)) != :ok ->
          {:error, :invalid_restart_policy}

        not Keyword.keyword?(Keyword.get(opts, :server_options, [])) ->
          {:error, :invalid_child_options}

        not (is_atom(tag) or is_binary(tag)) or is_nil(tag) ->
          {:error, :invalid_child_tag}

        placement not in [:owned, :independent] ->
          {:error, :invalid_placement}

        policy not in [:stop, :continue, :emit_orphan] ->
          {:error, :invalid_parent_policy}

        placement == :owned and policy != :stop ->
          {:error, :owned_child_cannot_survive_parent}

        placement == :independent and is_nil(context.jido) ->
          {:error, :jido_instance_required}

        policy == :emit_orphan and
            (is_nil(dispatch) or Effects.validate_dispatch(dispatch) != :ok) ->
          {:error, :invalid_orphan_dispatch}

        true ->
          {:ok, context,
           %{
             restart: Keyword.get(opts, :restart, :transient),
             meta: Keyword.get(opts, :meta, %{}),
             activation: context.activation,
             state: context.state,
             token: token,
             agent_id: context.agent_id,
             tag: tag,
             placement: placement,
             policy: policy,
             dispatch: dispatch,
             jido: context.jido,
             partition: context.partition
           }}
      end
    else
      {:error, :invalid_child_options}
    end
  end

  defp unique_options?(opts) do
    Keyword.keyword?(opts) and
      length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts)))
  end
end
