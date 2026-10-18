Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer.PersistenceTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server2", async: false

  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F
  alias JidoTest.Persistence.ProbeStore

  defmodule Storage do
    use Elixir.Agent
    @behaviour Jido.Persistence.Adapter
    def start_link(_), do: Elixir.Agent.start_link(fn -> %{read: :ok, write: :ok} end)

    def configure(opts, kind, mode),
      do: Elixir.Agent.update(opts[:control], &Map.put(&1, kind, mode))

    def get(key, opts) do
      case gate(:read, opts) do
        :ok -> ProbeStore.get(key, opts)
        error -> error
      end
    end

    def compare_and_swap(key, expected, value, opts) do
      %{rev: revision} = :erlang.binary_to_term(value, [:safe])
      mode = if revision == 0, do: :ok, else: Elixir.Agent.get(opts[:control], & &1.write)

      case mode do
        :ok ->
          ProbeStore.compare_and_swap(key, expected, value, opts)

        :gate ->
          :ok = wait(opts, :write)
          ProbeStore.compare_and_swap(key, expected, value, opts)

        :written_gate ->
          :ok = ProbeStore.compare_and_swap(key, expected, value, opts)
          wait(opts, :written)

        :unknown ->
          :ok = ProbeStore.compare_and_swap(key, expected, value, opts)
          {:error, :indeterminate}

        :crash ->
          exit(:storage_lost)

        result ->
          result
      end
    end

    defp gate(kind, opts) do
      case Elixir.Agent.get(opts[:control], &Map.fetch!(&1, kind)) do
        :gate -> wait(opts, kind)
        result -> result
      end
    end

    defp wait(opts, kind) do
      send(opts[:observer], {:storage, kind, self()})
      receive do: (:release -> :ok)
    end
  end

  defmodule Resource do
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    def init(init) do
      send(init.options[:observer], {:resource, self(), init})
      {:ok, init}
    end
  end

  defmodule Plugin do
    use Jido.Plugin
    def state_spec(_), do: {:resource, Zoi.integer() |> Zoi.default(7)}
    def child_spec(init), do: %{start: {Resource, :start_link, [init]}}
    def reduce(reduction, _), do: {:ok, reduction.plugin_state + 1}

    def dump(value, _, _), do: {:ok, %{saved_resource: value}}
    def load(%{saved_resource: value}, _, _), do: {:ok, value}

    def after_commit(_, commit, opts) do
      send(opts[:observer], {:committed, commit.state_version})
      :ok
    end
  end

  defmodule LocalValue do
    use Jido.Action, name: "server2_durable_local_value"
    def run(_, context), do: {:ok, %{context.agent_state | handle: self()}}
  end

  defmodule LocalAgent do
    use Jido.Agent, name: "server2_durable_local_agent"

    agent do
      schema Zoi.object(%{handle: Zoi.any() |> Zoi.default(nil)})
    end

    routes do
      route "work", LocalValue
    end
  end

  defmodule CustomAgent do
    use Jido.Agent, name: "server2_durable_custom_agent"

    agent do
      schema Zoi.object(%{handle: Zoi.any() |> Zoi.default(nil)})
    end

    routes do
      route "work", LocalValue
    end

    @impl Jido.Agent
    def checkpoint(agent, _), do: {:ok, %{id: agent.id}}
    @impl Jido.Agent
    def restore(%{id: id}, _), do: {:ok, instantiate!(id: id)}
  end

  setup do
    store = start_supervised!(ProbeStore)
    control = start_supervised!(Storage)
    observer = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), observer)
    opts = [store: store, control: control, observer: observer]
    %{agent: F.agent(), adapter: {Storage, opts}, storage: opts, observer: observer}
  end

  defp start(c, opts) do
    F.start(
      %{agent: c.agent, runner: Jido.exec_runner_name(c.jido)},
      Keyword.merge([jido: c.jido, persistence: c.adapter], opts)
    )
  end

  defp ready(c, opts \\ []) do
    server = start(c, opts)
    assert Server.await_ready(server) == :ok
    server
  end

  defp load(c),
    do:
      Jido.Persistence.load_agent_with_revision(c.adapter, c.agent.module, c.agent.id,
        instance: c.jido
      )

  defp record(c) do
    {:ok, ref} = Jido.agent_ref(c.jido, c.agent.id)
    {:ok, bytes} = ProbeStore.get(Jido.Persistence.agent_key(ref), c.storage)
    :erlang.binary_to_term(bytes, [:safe])
  end

  defp rewrite(c, fun) do
    key = Jido.Persistence.agent_key(elem(Jido.agent_ref(c.jido, c.agent.id), 1))
    ProbeStore.put(key, :erlang.term_to_binary(fun.(record(c))), c.storage)
  end

  defp failure(c, opts \\ []) do
    # Gate the read so the test can monitor the root before a restore fault.
    Storage.configure(c.storage, :read, :gate)
    server = start(c, Keyword.merge([persistence_mode: :restore], opts))
    root = Server.activation(server)
    assert_receive {:storage, :read, task}, 1_000
    {server, root, task}
  end

  @tag obligation: ["jido.agent_server2.I77", "jido.agent_server2.I78"]
  test "required save precedes publication; reads and caller waits stay independent", c do
    server = ready(c, turn_timeout: 60_000)
    assert {:ok, initial, 0} = load(c)
    assert initial == c.agent
    Storage.configure(c.storage, :write, :gate)
    pending = Server.submit(server, F.signal())
    assert_receive {:storage, :write, writer}, 1_000
    assert %{active: %{stage: :saving}, state_version: 0} = Server.status(server)
    assert Server.agent(server) == c.agent
    assert Server.await(pending, 0) == {:error, :timeout}
    assert Server.cancel(server) == {:error, :commit_in_progress}
    assert record(c).rev == 0
    queued = Server.submit(server, F.signal())
    assert Server.status(server).admission.postponed == 1
    # The turn deadline no longer cancels an accepted required save.
    send(server, {:turn_timeout, Server.status(server).active.turn_id})
    Storage.configure(c.storage, :write, :ok)
    send(writer, :release)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(pending)
    assert {:ok, %{state: %{count: 2}}, []} = Server.await(queued)
    assert {:ok, %{state: %{count: 2}}, 2} = load(c)
    assert Server.status(server).state_version == 2
    F.clean(Jido.exec_runner_name(c.jido))
  end

  @tag obligation: ["jido.agent_server2.I79", "jido.agent_server2.I80"]
  test "new activation restores Agent revision and Plugin state before resources start", c do
    definition = Jido.Agent.definition(c.agent)

    {:ok, definition} =
      Jido.Agent.define(
        Map.put(Map.from_struct(definition), :extensions, [
          JidoTest.AgentContract.contribution(Plugin, %{observer: c.observer})
        ])
      )

    c = %{c | agent: Jido.Agent.instantiate!(definition, id: c.agent.id)}
    server = ready(c)
    assert_receive {:resource, old_resource, %{plugin_state: 7, state_version: 0}}, 1_000
    assert {:ok, _, []} = Server.call(server, F.signal())
    assert_receive {:committed, 1}, 1_000
    assert record(c).checkpoint.agent.state.resource == %{saved_resource: 8}
    :ok = Server.stop(server)
    F.down(old_resource)
    restored = ready(c, persistence_mode: :restore)
    assert_receive {:resource, new_resource, %{plugin_state: 8, state_version: 1}}, 1_000
    assert new_resource != old_resource
    assert Server.agent(restored).state == %{count: 1, resource: 8}
    assert Server.status(restored).state_version == 1
    assert {:ok, _, []} = Server.call(restored, F.signal())
    assert_receive {:committed, 2}, 1_000
    assert {:ok, %{state: %{count: 2, resource: 9}}, 2} = load(c)
  end

  @tag obligation: ["jido.agent_server2.I73", "jido.agent_server2.I79", "jido.agent_server2.I80"]
  test "Plugin recovery waits for the durable checkpoint before it reads initialization data",
       c do
    agent =
      Jido.Agent.define!(%{
        name: "durable_plugin_recovery",
        schema: c.agent.schema,
        extensions: [
          %{id: Plugin.id(), provider: Plugin, vsn: Plugin.vsn(), data: %{observer: c.observer}}
        ],
        routes: c.agent.routes
      })
      |> Jido.Agent.instantiate!(id: c.agent.id)

    c = %{c | agent: agent}
    server = ready(c)
    assert_receive {:resource, resource, %{plugin_state: 7, state_version: 0}}, 1_000
    assert {:ok, committed, []} = Server.call(server, F.signal())
    assert_receive {:committed, 1}, 1_000
    {_phase, data} = :sys.get_state(server)
    Storage.configure(c.storage, :read, :gate)
    Process.exit(resource, :kill)
    F.down(server)
    assert_receive {:storage, :read, reader}, 1_000

    # The supervisor can be waiting for the postponed Plugin start. Read the
    # worker identity from its checkpoint table without calling the supervisor.
    replacement = :ets.lookup_element(data.activation_state, :worker, 2)
    request = :gen_statem.send_request(replacement, {:plugin_init, Plugin})
    assert Server.status(replacement).phase == :initializing
    assert :gen_statem.wait_response(request, 0) == :timeout
    refute_received {:resource, _, _}

    Storage.configure(c.storage, :read, :ok)
    send(reader, :release)

    assert {:reply, {:ok, %{plugin_state: 8, state_version: 1}}} =
             :gen_statem.wait_response(request, 1_000)

    assert_receive {:resource, fresh, %{plugin_state: 8, state_version: 1}}, 1_000
    assert fresh != resource
    assert Server.await_ready(replacement) == :ok
    assert Server.agent(replacement) == committed
  end

  @tag obligation: ["jido.agent_server2.I79", "jido.agent_server2.I81"]
  test "worker death after durable write restores stored commit without replay", c do
    server = ready(c)
    root = Server.activation(server)
    Storage.configure(c.storage, :write, :written_gate)
    Server.submit(server, F.signal())
    assert_receive {:storage, :written, writer}, 1_000
    assert Server.agent(server).state.count == 0
    assert record(c).rev == 1
    Process.exit(server, :kill)
    F.down(server)
    F.down(writer)

    assert_eventually(
      is_pid(Server.Supervisor.worker(root)) and Server.Supervisor.worker(root) != server
    )

    replacement = Server.Supervisor.worker(root)
    assert Server.await_ready(replacement) == :ok
    assert Server.agent(replacement).state.count == 1
    assert Server.status(replacement).state_version == 1
    assert record(c).rev == 1
    F.clean(Jido.exec_runner_name(c.jido))
  end

  for {name, result, revision} <- [
        {"conflict", {:error, :conflict}, 0},
        {"rejection", {:error, {:rejected, :read_only}}, 0},
        {"unknown", :unknown, 1},
        {"adapter exit", :crash, 0},
        {"invalid result", :invalid, 0}
      ] do
    @tag obligation: "jido.agent_server2.I78"
    test "required write #{name} stops the activation without success", c do
      server = ready(c)
      root = Server.activation(server)
      Storage.configure(c.storage, :write, unquote(Macro.escape(result)))
      assert {:error, %Jido.Error.ExecutionError{}} = Server.call(server, F.signal())
      F.down(root)
      assert record(c).rev == unquote(revision)
      F.clean(Jido.exec_runner_name(c.jido))
    end
  end

  @tag obligation: "jido.agent_server2.I78"
  test "save timeout stops and confirms the storage task and activation", c do
    server = ready(c, persistence_timeout: 100)
    root = Server.activation(server)
    Storage.configure(c.storage, :write, :gate)
    pending = Server.submit(server, F.signal())
    assert_receive {:storage, :write, writer}, 1_000

    assert {:error, %Jido.Error.ExecutionError{details: %{reason: :indeterminate}}} =
             Server.await(pending)

    F.down(root)
    F.down(writer)
    assert record(c).rev == 0
  end

  @tag obligation: "jido.agent_server2.I79"
  test "restore missing record fails; create cannot replace an existing record", c do
    {_server, root, task} = failure(c)
    Storage.configure(c.storage, :read, :ok)
    send(task, :release)
    F.down(root)
    server = ready(c)
    assert {:ok, _, []} = Server.call(server, F.signal())
    :ok = Server.stop(server)

    root =
      F.start_activation(%{agent: c.agent, runner: Jido.exec_runner_name(c.jido)},
        jido: c.jido,
        persistence: c.adapter
      )

    F.down(root)
    assert record(c).rev == 1
  end

  for {name, update} <- [
        {"identity", quote(do: &Map.put(&1, :agent_id, "other"))},
        {"revision", quote(do: &Map.put(&1, :rev, -1))},
        {"version", quote(do: &Map.put(&1, :vsn, 999))},
        {"state",
         quote(
           do: &put_in(&1, [:checkpoint, Access.key!(:agent), Access.key!(:state), :count], "bad")
         )},
        {"definition",
         quote(
           do:
             &update_in(&1, [:checkpoint, Access.key!(:agent)], fn definition ->
               %{definition | routes: :invalid}
             end)
         )},
        {"format", quote(do: &Map.put(&1, :fmt, 999))}
      ] do
    @tag obligation: "jido.agent_server2.I79"
    test "restore rejects corrupt #{name} before readiness", c do
      server = ready(c)
      :ok = Server.stop(server)
      rewrite(c, unquote(update))
      {_server, root, task} = failure(c)
      send(task, :release)
      F.down(root)
    end
  end

  @tag obligation: "jido.agent_server2.I79"
  test "bounded load and read faults never fall back to fresh state", c do
    server = ready(c)
    :ok = Server.stop(server)
    {_server, root, task} = failure(c, persistence_timeout: 100)
    F.down(root)
    F.down(task)
    Storage.configure(c.storage, :read, {:error, :unavailable})

    root =
      F.start_activation(%{agent: c.agent, runner: Jido.exec_runner_name(c.jido)},
        jido: c.jido,
        persistence: c.adapter,
        persistence_mode: :restore
      )

    F.down(root)
    assert record(c).rev == 0
  end

  @tag obligation: "jido.agent_server2.I82"
  test "durable save rejects local handles without changing local state rules", c do
    c = %{c | agent: LocalAgent.instantiate!(id: c.agent.id)}
    local = start(c, persistence: false)
    assert :ok = Server.await_ready(local)
    assert {:ok, %{state: %{handle: handle}}, []} = Server.call(local, F.signal())
    assert is_pid(handle)
    :ok = Server.stop(local)

    server = ready(c)
    root = Server.activation(server)
    assert {:error, %Jido.Error.ExecutionError{}} = Server.call(server, F.signal())
    F.down(root)
    assert {:ok, %{state: %{handle: nil}}, 0} = load(c)
  end

  @tag obligation: "jido.agent_server2.I82"
  test "custom Agent checkpoint conversion protects portable records", c do
    c = %{c | agent: CustomAgent.instantiate!(id: c.agent.id, state: %{handle: self()})}
    server = ready(c)
    assert {:ok, %{state: %{handle: handle}}, []} = Server.call(server, F.signal())
    assert is_pid(handle)
    assert record(c).checkpoint.state_format == :custom
    :ok = Server.stop(server)
    restored = ready(c, persistence_mode: :restore)
    assert Server.agent(restored).state.handle == nil
    assert Server.status(restored).state_version == 1
  end

  @tag obligation: ["jido.agent_server2.I79", "jido.agent_server2.I80"]
  test "Plugins do not start until the saved record passes validation", c do
    definition =
      Jido.Agent.define!(%{
        name: "durable_plugin_order",
        extensions: [
          %{id: Plugin.id(), provider: Plugin, vsn: Plugin.vsn(), data: %{observer: c.observer}}
        ]
      })

    c = %{c | agent: Jido.Agent.instantiate!(definition, id: c.agent.id)}
    server = ready(c)
    assert_receive {:resource, old_resource, _}, 1_000
    :ok = Server.stop(server)
    F.down(old_resource)
    rewrite(c, &Map.put(&1, :rev, -1))
    {server, root, task} = failure(c)
    assert %{phase: :initializing, ready?: false} = Server.status(server)
    assert [{Server, ^server, :worker, _}] = Supervisor.which_children(root)
    send(task, :release)
    F.down(root)
    # Root DOWN is the completion barrier; no provisional resource could remain.
    refute_received {:resource, _, _}
  end

  @tag obligation: "jido.agent_server2.I83"
  test "runtime configuration is explicit and persistence can inherit the instance adapter", c do
    for opts <- [
          [persistence_timeout: :infinity],
          [persistence_timeout: -1],
          [persistence_mode: :automatic]
        ] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Server.activation_options([agent: c.agent, jido: c.jido] ++ opts)
    end

    assert {:error, %Jido.Error.ValidationError{}} =
             Server.start_link(
               agent: c.agent,
               jido: c.jido,
               persistence: c.adapter
             )

    assert {:error, %Jido.Error.ValidationError{}} =
             Server.activation_options(
               agent: c.agent,
               runner: Jido.exec_runner_name(c.jido),
               persistence: c.adapter
             )

    instance = Module.concat(__MODULE__, "Instance#{System.unique_integer([:positive])}")

    start_supervised!(
      {Jido, name: instance, namespace: "jido/durable/#{instance}", persistence: c.adapter}
    )

    c = %{c | jido: instance}
    server = ready(c, persistence: :inherit)
    assert record(c).rev == 0
    assert {:ok, _, []} = Server.call(server, F.signal())
    assert record(c).rev == 1
  end

  @tag obligation: ["jido.agent_server2.I77", "jido.agent_server2.I78"]
  test "expected revision rejects a record behind the live revision", c do
    server = ready(c)
    root = Server.activation(server)
    initial = record(c)
    assert {:ok, _, []} = Server.call(server, F.signal())
    rewrite(c, fn _ -> initial end)

    assert {:error, %Jido.Error.ExecutionError{details: %{reason: :conflict}}} =
             Server.call(server, F.signal())

    F.down(root)
    assert record(c).rev == 0
  end

  @tag obligation: ["jido.agent_server2.I78", "jido.agent_server2.I80"]
  test "uncertain write runs no hooks or directives and restore does not replay them", c do
    definition =
      Jido.Agent.define!(%{
        name: "durable_no_replay",
        extensions: [
          %{id: Plugin.id(), provider: Plugin, vsn: Plugin.vsn(), data: %{observer: c.observer}}
        ],
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        routes: [%{path: "work", handler: %{kind: :action, target: F.Work}}]
      })

    c = %{c | agent: Jido.Agent.instantiate!(definition, id: c.agent.id)}
    server = ready(c)
    root = Server.activation(server)
    assert_receive {:resource, _, _}, 1_000
    Storage.configure(c.storage, :write, :unknown)
    signal = Jido.Signal.new!("saved.effect", %{}, source: "/server2-contract")

    directive = %Jido.Agent.Directive.Emit{
      signal: signal,
      dispatch: {:pid, target: self(), delivery_mode: :sync}
    }

    assert {:error, _} = Server.call(server, F.signal(%{mode: :batch, directives: [directive]}))
    F.down(root)
    restored = ready(c, persistence_mode: :restore)
    assert Server.status(restored).state_version == 1
    :ok = Server.stop(restored)
    refute_received {:committed, _}
    refute_received {:signal, _}
  end

  @tag obligation: ["jido.agent_server2.I81", "jido.agent_server2.I78"]
  test "local publication failure after durable save stops and permits explicit restore", c do
    server = ready(c)
    root = Server.activation(server)
    {_, data} = :sys.get_state(server)
    :ets.insert(data.activation_state, {:checkpoint, c.agent, 99})
    assert {:error, _} = Server.call(server, F.signal())
    F.down(root)
    assert record(c).rev == 1
    restored = ready(c, persistence_mode: :restore)
    assert Server.agent(restored).state.count == 1
    assert Server.status(restored).state_version == 1
  end

  @tag obligation: "jido.agent_server2.I82"
  test "nonportable initial state fails create without saving a record", c do
    c = %{c | agent: LocalAgent.instantiate!(id: c.agent.id, state: %{handle: self()})}

    root =
      F.start_activation(%{agent: c.agent, runner: Jido.exec_runner_name(c.jido)},
        jido: c.jido,
        persistence: c.adapter
      )

    F.down(root)
    assert load(c) == {:error, :not_found}
  end

  @tag obligation: "jido.agent_server2.I78"
  test "late successful write is indeterminate even when its reply precedes the timer", c do
    server = ready(c, persistence_timeout: 100)
    root = Server.activation(server)
    Storage.configure(c.storage, :write, :gate)
    pending = Server.submit(server, F.signal())
    assert_receive {:storage, :write, writer}, 1_000
    :ok = :sys.suspend(server)

    try do
      send(writer, :release)
      F.down(writer)
      F.elapsed(120)
    after
      :sys.resume(server)
    end

    assert {:error, %Jido.Error.ExecutionError{details: %{reason: :indeterminate}}} =
             Server.await(pending)

    F.down(root)
    assert record(c).rev == 1
    restored = ready(c, persistence_mode: :restore)
    assert Server.agent(restored).state.count == 1
  end

  @tag obligation: "jido.agent_server2.I78"
  test "lost storage task ends the activation and releases queued callers", c do
    server = ready(c)
    root = Server.activation(server)
    Storage.configure(c.storage, :write, :gate)
    pending = Server.submit(server, F.signal())
    assert_receive {:storage, :write, writer}, 1_000
    queued = Server.submit(server, F.signal())
    assert Server.status(server).admission.postponed == 1
    Process.exit(writer, :kill)
    assert {:error, %Jido.Error.ExecutionError{}} = Server.await(pending)
    F.down(root)
    assert {:error, %Jido.Error.ExecutionError{}} = Server.await(queued)
    assert record(c).rev == 0
    F.clean(Jido.exec_runner_name(c.jido))
  end
end
