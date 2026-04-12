defmodule Examples.PhoenixIssueTriage.IssueTriage do
  @moduledoc """
  Public domain API for interacting with the issue triage pod.

  This is the module controllers, LiveViews, and jobs should call. It wraps the
  raw pod runtime with semantic domain operations and hides low-level runtime
  details such as sensor child lookup, lazy role activation, and mutation APIs.
  """

  alias Examples.PhoenixIssueTriage.IssueTriage.{Plugins, Pod, Sensors}
  alias Examples.PhoenixIssueTriage.IssueTriage.Agents.PublisherAgent
  alias Jido.AgentServer
  alias Jido.Memory.Agent, as: MemoryAgent
  alias Jido.Pod, as: PodRuntime
  alias Jido.Pod.Mutation
  alias Jido.Pod.Topology
  alias Jido.Sensor.Runtime, as: SensorRuntime
  alias Jido.Signal
  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent

  @pod_manager :example_issue_triage_pods
  @publisher_manager :example_issue_triage_publishers
  @ops_plugin Plugins.IssueRunOpsPlugin
  @webhook_sensor Sensors.IssueWebhookSensor
  @default_source "/examples/phoenix_issue_triage"

  @type run_server :: AgentServer.server()
  @type run_key :: term()
  @type role_name :: PodRuntime.node_name()

  @spec open_run(run_key(), keyword()) :: {:ok, pid()} | {:error, term()}
  def open_run(key, opts \\ []) do
    PodRuntime.get(@pod_manager, key, opts)
  end

  @spec open_run(atom(), run_key(), keyword()) :: {:ok, pid()} | {:error, term()}
  def open_run(manager, key, opts) when is_atom(manager) do
    PodRuntime.get(manager, key, opts)
  end

  @spec topology(module() | run_server()) :: {:ok, Topology.t()} | {:error, term()}
  def topology(source \\ Pod) do
    PodRuntime.fetch_topology(source)
  end

  @spec status(run_server()) :: {:ok, map()} | {:error, term()}
  def status(run) do
    with {:ok, server_state} <- AgentServer.state(run),
         {:ok, snapshots} <- PodRuntime.nodes(run) do
      agent = server_state.agent

      {:ok,
       %{
         pod_id: agent.id,
         pod_module: server_state.agent_module,
         status: agent.state.status,
         current_stage: agent.state.current_stage,
         issue_id: agent.state.issue_id,
         repo: agent.state.repo,
         title: agent.state.title,
         requires_research?: agent.state.requires_research?,
         triage_summary: agent.state.triage_summary,
         research_summary: agent.state.research_summary,
         review_outcome: agent.state.review_outcome,
         review_summary: agent.state.review_summary,
         published_artifact: agent.state.published_artifact,
         ops: Map.get(agent.state, :ops, %{}),
         roles: summarize_roles(snapshots),
         memory: summarize_memory(agent),
         thread: summarize_thread(agent)
       }}
    end
  end

  @spec role_snapshots(run_server()) ::
          {:ok, %{role_name() => PodRuntime.node_snapshot()}} | {:error, term()}
  def role_snapshots(run) do
    PodRuntime.nodes(run)
  end

  @spec lookup_role(run_server(), role_name()) :: {:ok, pid()} | :error | {:error, term()}
  def lookup_role(run, role) do
    PodRuntime.lookup_node(run, role)
  end

  @spec ensure_role(run_server(), role_name(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_role(run, role, opts \\ []) do
    PodRuntime.ensure_node(run, role, opts)
  end

  @spec dispatch_to_pod(run_server(), String.t(), map(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def dispatch_to_pod(run, signal_type, payload \\ %{}, opts \\ []) do
    AgentServer.call(run, build_signal(signal_type, payload, opts))
  end

  @spec dispatch_to_role(run_server(), role_name(), String.t(), map(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def dispatch_to_role(run, role, signal_type, payload \\ %{}, opts \\ []) do
    with {:ok, pid} <- ensure_role(run, role) do
      AgentServer.call(pid, build_signal(signal_type, payload, opts))
    end
  end

  @spec sensor_pids(run_server()) :: {:ok, %{module() => pid()}} | {:error, term()}
  def sensor_pids(run) do
    with {:ok, state} <- AgentServer.state(run) do
      sensors =
        state.children
        |> Map.values()
        |> Enum.reduce(%{}, fn child, acc ->
          case child.tag do
            {:sensor, @ops_plugin, sensor_module} -> Map.put(acc, sensor_module, child.pid)
            _other -> acc
          end
        end)

      {:ok, sensors}
    end
  end

  @spec ingest_issue(run_server(), map()) :: :ok | {:error, term()}
  def ingest_issue(run, payload) when is_map(payload) do
    with {:ok, sensor_pid} <- sensor_pid(run, @webhook_sensor) do
      SensorRuntime.event(sensor_pid, {:issue_opened, payload})
    end
  end

  @spec process_issue(run_server(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def process_issue(run, payload, opts \\ []) when is_map(payload) do
    with :ok <- ingest_issue(run, payload),
         {:ok, ingested} <- await_stage(run, :ingested, opts),
         {:ok, _agent} <- start_triage(run, ingested),
         {:ok, triaged} <- await_stage(run, :triaged, opts),
         {:ok, after_research} <- maybe_research(run, triaged, opts),
         {:ok, _agent} <- start_review(run, after_research),
         {:ok, reviewed} <- await_stage(run, :reviewed, opts) do
      {:ok, reviewed}
    end
  end

  @spec publish_run(run_server(), keyword()) :: {:ok, map()} | {:error, term()}
  def publish_run(run, opts \\ []) do
    with {:ok, current} <- status(run),
         :ok <- ensure_publishable(current),
         {:ok, _mutation_report} <- add_publisher_role(run),
         {:ok, _agent} <- start_publish(run, current),
         {:ok, published} <- await_stage(run, :published, opts) do
      {:ok, published}
    end
  end

  @spec add_publisher_role(run_server()) ::
          {:ok, PodRuntime.mutation_report() | :already_present} | {:error, term()}
  def add_publisher_role(run) do
    with {:ok, topology} <- topology(run) do
      if Map.has_key?(topology.nodes, :publisher) do
        {:ok, :already_present}
      else
        PodRuntime.mutate(
          run,
          [
            Mutation.add_node(
              :publisher,
              %{
                agent: PublisherAgent,
                manager: @publisher_manager,
                activation: :lazy,
                initial_state: %{role: "publisher"}
              },
              depends_on: [:reviewer]
            )
          ]
        )
      end
    end
  end

  @spec mutate(run_server(), [Mutation.t() | term()], keyword()) ::
          {:ok, PodRuntime.mutation_report()} | {:error, PodRuntime.mutation_report() | term()}
  def mutate(run, ops, opts \\ []) do
    PodRuntime.mutate(run, ops, opts)
  end

  @spec shutdown(run_server(), term()) :: :ok
  def shutdown(run, reason \\ :normal) do
    GenServer.stop(run, reason)
  end

  @spec await_stage(run_server(), atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def await_stage(run, stage, opts \\ []) do
    await_status(run, fn status -> status.current_stage == stage end, opts)
  end

  defp maybe_research(run, %{requires_research?: true} = _status, opts) do
    with {:ok, refreshed} <- status(run),
         {:ok, _agent} <- start_research(run, refreshed),
         {:ok, researched} <- await_stage(run, :researched, opts) do
      {:ok, researched}
    end
  end

  defp maybe_research(_run, status, _opts), do: {:ok, status}

  defp start_triage(run, status) do
    dispatch_to_role(run, :triager, "issue.triage.requested", %{
      issue_id: status.issue_id,
      repo: status.repo,
      title: status.title,
      body: current_body(run),
      labels: current_labels(run),
      requires_research: status.requires_research?
    })
  end

  defp start_research(run, status) do
    dispatch_to_role(run, :researcher, "issue.research.requested", %{
      issue_id: status.issue_id,
      repo: status.repo,
      title: status.title,
      body: current_body(run),
      triage_summary: status.triage_summary,
      classification: current_classification(run),
      priority: current_priority(run)
    })
  end

  defp start_review(run, status) do
    dispatch_to_role(run, :reviewer, "issue.review.requested", %{
      issue_id: status.issue_id,
      repo: status.repo,
      triage_summary: status.triage_summary,
      classification: current_classification(run),
      priority: current_priority(run),
      research_summary: status.research_summary
    })
  end

  defp start_publish(run, status) do
    dispatch_to_role(run, :publisher, "issue.publish.requested", %{
      issue_id: status.issue_id,
      repo: status.repo,
      triage_summary: status.triage_summary,
      review_summary: status.review_summary
    })
  end

  defp await_status(run, fun, opts) do
    timeout = Keyword.get(opts, :timeout, 2_000)
    interval = Keyword.get(opts, :interval, 10)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_await_status(run, fun, deadline, interval)
  end

  defp do_await_status(run, fun, deadline, interval) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      case status(run) do
        {:ok, current} ->
          if fun.(current) do
            {:ok, current}
          else
            Process.sleep(interval)
            do_await_status(run, fun, deadline, interval)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp sensor_pid(run, sensor_module) do
    with {:ok, sensors} <- sensor_pids(run) do
      case Map.fetch(sensors, sensor_module) do
        {:ok, pid} -> {:ok, pid}
        :error -> {:error, {:sensor_not_found, sensor_module}}
      end
    end
  end

  defp current_body(run) do
    {:ok, state} = AgentServer.state(run)
    state.agent.state.body
  end

  defp current_labels(run) do
    {:ok, state} = AgentServer.state(run)
    state.agent.state.labels
  end

  defp current_classification(run) do
    {:ok, state} = AgentServer.state(run)
    state.agent.state.classification
  end

  defp current_priority(run) do
    {:ok, state} = AgentServer.state(run)
    state.agent.state.priority
  end

  defp build_signal(type, payload, opts) do
    signal_opts =
      opts
      |> Keyword.take([
        :source,
        :subject,
        :jido_metadata,
        :trace_id,
        :correlation_id,
        :causation_id
      ])
      |> Keyword.put_new(:source, @default_source)

    Signal.new!(type, payload, signal_opts)
  end

  defp summarize_roles(snapshots) do
    Map.new(snapshots, fn {name, snapshot} ->
      {name,
       %{
         status: snapshot.status,
         pid: snapshot.pid,
         owner: snapshot.owner,
         activation: snapshot.node.activation
       }}
    end)
  end

  defp summarize_memory(agent) do
    case MemoryAgent.get(agent) do
      nil ->
        %{present?: false}

      memory ->
        %{
          present?: true,
          id: memory.id,
          rev: memory.rev,
          spaces: Map.keys(memory.spaces) |> Enum.sort()
        }
    end
  end

  defp summarize_thread(agent) do
    case ThreadAgent.get(agent) do
      nil ->
        %{present?: false}

      thread ->
        %{
          present?: true,
          id: thread.id,
          rev: thread.rev,
          entry_count: Thread.entry_count(thread)
        }
    end
  end

  defp ensure_publishable(%{review_outcome: :approved}), do: :ok
  defp ensure_publishable(_status), do: {:error, :not_publishable}
end
