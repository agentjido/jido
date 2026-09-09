defmodule Jido.AgentServer.CommitBoundaryTest do
  use JidoTest.Case, async: false

  alias Jido.Agent.Plugin.Contribution
  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Turn.Outcome
  alias Jido.Signal

  @moduletag capture_log: true

  defmodule Effect do
    @moduledoc false
    defstruct [:label, :sink, :observer, :gate]
  end

  defmodule AgentFacet do
    @moduledoc false
    use Jido.Agent.Plugin

    def directives(_opts), do: [Effect]
    def validate_directive(%Effect{} = effect, _opts), do: {:ok, effect}

    def contribute(transition, _opts) do
      {:ok, %Contribution{plugin: transition.plugin}}
    end
  end

  defmodule ServerFacet do
    @moduledoc false
    use Jido.AgentServer.Plugin

    def dispatch(_runtime, %Effect{} = effect, _context, _opts) do
      if effect.sink, do: Elixir.Agent.update(effect.sink, &(&1 ++ [effect.label]))
      if effect.observer, do: send(effect.observer, {:effect_started, effect.label, self()})

      if effect.gate do
        receive do
          {:release, gate} when gate == effect.gate -> :ok
        end
      else
        :ok
      end
    end
  end

  defmodule Package do
    @moduledoc false
    use Jido.Plugin, agent: AgentFacet, agent_server: ServerFacet
  end

  defmodule CommitEffects do
    @moduledoc false
    use Jido.Action,
      name: "commit_boundary_effects",
      schema: Zoi.object(%{effects: Zoi.list(Zoi.map())})

    def run(%{effects: effects}, context) do
      directives = Enum.map(effects, &struct!(Effect, &1))
      {:ok, %{context.agent_state | count: context.agent_state.count + 1}, directives}
    end
  end

  defmodule WriteThenReturnInvalidState do
    @moduledoc false
    use Jido.Action,
      name: "commit_boundary_external_write",
      schema: Zoi.object(%{observer: Zoi.pid()})

    def run(%{observer: observer}, context) do
      send(observer, :external_write_completed)
      {:ok, %{context.agent_state | count: "invalid"}}
    end
  end

  defmodule Agent do
    @moduledoc false
    use Jido.Agent,
      name: "commit_boundary_agent",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      routes: [
        {"commit.effects", CommitEffects},
        {"commit.external_invalid", WriteThenReturnInvalidState}
      ],
      plugins: [Package]
  end

  test "three Directives run in returned order after one complete commit", %{jido: jido} do
    sink = start_supervised!({Elixir.Agent, fn -> [] end})
    {:ok, server} = Jido.start_agent(jido, Agent, id: unique_id("commit-order"))

    effects = Enum.map([:first, :second, :third], &%{label: &1, sink: sink})
    signal = Signal.new!("commit.effects", %{effects: effects}, source: "/test")

    assert {:ok, committed} = Server.call(server, signal)
    assert committed.state.count == 1
    assert Server.snapshot(server).state_version == 1
    eventually(fn -> Server.status(server).phase == :idle end)
    assert Elixir.Agent.get(sink, & &1) == [:first, :second, :third]
  end

  test "a Directive timeout can follow an external effect and cannot undo the commit", %{
    jido: jido
  } do
    observer = self()

    policy = fn reason, outcome ->
      send(observer, {:settled, reason, outcome})
      :continue
    end

    {:ok, server} =
      Jido.start_agent(jido, Agent,
        id: unique_id("commit-timeout"),
        directive_timeout: 25,
        error_policy: policy
      )

    gate = make_ref()

    signal =
      Signal.new!(
        "commit.effects",
        %{effects: [%{label: :before_timeout, observer: observer, gate: gate}]},
        source: "/test"
      )

    assert {:ok, committed} = Server.call(server, signal)
    assert_receive {:effect_started, :before_timeout, worker}, 1_000

    assert_receive {:settled, %Jido.Error.TimeoutError{},
                    %Outcome{status: :timed_out, stage: :directive, committed?: true}},
                   2_000

    refute Process.alive?(worker)
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
  end

  test "external Action work remains when candidate validation fails before storage", %{
    jido: jido
  } do
    persistence = persistence("validation")
    id = unique_id("commit-validation")

    {:ok, server} =
      Jido.start_agent(jido, Agent, id: id, persistence: persistence, restore: false)

    signal =
      Signal.new!("commit.external_invalid", %{observer: self()}, source: "/test")

    assert {:error, %Jido.Error.ValidationError{}} = Server.call(server, signal)
    assert_receive :external_write_completed
    assert Server.snapshot(server).state_version == 0

    assert {:ok, initial, 0} =
             Jido.Persistence.load_agent_with_revision(persistence, Agent, id, instance: jido)

    assert initial.state == %{count: 0}
  end

  for blocked_index <- [0, 1] do
    @blocked_index blocked_index
    test "an ordinary Directive batch is not replayed after loss at index #{@blocked_index}", %{
      jido: jido
    } do
      persistence = persistence("non_replay_#{@blocked_index}")
      id = unique_id("commit-non-replay")
      sink = start_supervised!({Elixir.Agent, fn -> [] end})

      opts = [
        id: id,
        persistence: persistence,
        restore: false,
        restart: :temporary,
        debug: true
      ]

      {:ok, server} = Jido.start_agent(jido, Agent, opts)
      gate = make_ref()

      effects =
        Enum.map(0..2, fn index ->
          if index == @blocked_index do
            %{label: index, sink: sink, observer: self(), gate: gate}
          else
            %{label: index, sink: sink}
          end
        end)

      signal = Signal.new!("commit.effects", %{effects: effects}, source: "/test")

      assert {:ok, committed} = Server.call(server, signal)
      assert_receive {:effect_started, @blocked_index, worker}, 1_000
      assert Elixir.Agent.get(sink, & &1) == Enum.to_list(0..@blocked_index)

      server_ref = Process.monitor(server)
      worker_ref = Process.monitor(worker)
      Process.exit(server, :kill)
      assert_receive {:DOWN, ^server_ref, :process, ^server, :killed}, 1_000
      assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 1_000
      eventually(fn -> Jido.whereis_agent(jido, id) == nil end)

      assert {:ok, restored} =
               Jido.start_agent(jido, Agent,
                 id: id,
                 persistence: persistence,
                 restore: :required,
                 restart: :temporary,
                 debug: true
               )

      assert Server.snapshot(restored) == %{agent: committed, state_version: 1}
      assert {:ok, []} = Server.recent_events(restored)
      assert Elixir.Agent.get(sink, & &1) == Enum.to_list(0..@blocked_index)
      refute_receive {:effect_started, _label, _worker}, 100
    end
  end

  defp persistence(label) do
    table = String.to_atom("commit_boundary_#{label}_#{System.unique_integer([:positive])}")
    {Jido.Persistence.ETS, table: table}
  end
end
