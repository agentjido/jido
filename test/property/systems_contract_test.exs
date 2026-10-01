defmodule JidoTest.Property.SystemsContractTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Persistence
  alias JidoTest.Property.Fuzz
  alias Jido.Topology.Controller

  defmodule First do
    use Jido.Plugin
    @impl true
    def state_spec(_), do: {:first, Zoi.integer() |> Zoi.default(0)}
    @impl true
    def prepare(input, _) do
      case input.signal.data.mode do
        "prepare_error" -> {:error, :prepare_denied}
        "raise" -> raise "property prepare fault"
        "nonportable" -> {:ok, <<1::1>>}
        _ -> {:ok, %{before: input.agent_state.value}}
      end
    end

    @impl true
    def reduce(input, _), do: {:ok, input.plugin_state + input.signal.data.amount}
  end

  defmodule Second do
    use Jido.Plugin
    @impl true
    def state_spec(_), do: {:second, Zoi.integer() |> Zoi.default(0)}
    @impl true
    def prepare(input, _), do: {:ok, %{before: input.agent_state.value, marker: "second"}}
    @impl true
    def reduce(input, _) do
      if input.signal.data.mode == "reduce_error",
        do: {:error, :reduce_denied},
        else: {:ok, input.state.first}
    end
  end

  defmodule Change do
    use Jido.Action,
      name: "property_systems_change",
      schema: Zoi.object(%{mode: Zoi.string(), amount: Zoi.integer()})

    @impl true
    def run(%{mode: mode, amount: amount}, context) do
      first = context.plugin_inputs[First].prepared
      second = context.plugin_inputs[Second].prepared

      state = %{
        context.agent_state
        | value: context.agent_state.value + amount,
          prepared: [first.before, second.before],
          marker: second.marker
      }

      state = if mode == "tamper", do: %{state | first: state.first + 1}, else: state
      {:ok, state}
    end
  end

  defmodule PluginAgent do
    use Jido.Agent, name: "property_systems_plugin"

    agent do
      schema Zoi.object(%{
               value: Zoi.integer() |> Zoi.default(0),
               prepared: Zoi.list(Zoi.integer()) |> Zoi.default([]),
               marker: Zoi.string() |> Zoi.default("")
             })

      plugin First
      plugin Second
    end

    routes do
      route "property.systems.change", Change
    end
  end

  defmodule StateAgent do
    use Jido.Agent, name: "property_systems_state"

    agent do
      schema Zoi.object(%{value: Zoi.any()})
    end
  end

  defmodule Member do
    use Jido.Agent, name: "property_systems_member"

    agent do
      schema Zoi.object(%{value: Zoi.any() |> Zoi.default(0)})
    end
  end

  for {variant, runs, milliseconds} <- [{:property, 30, 10_000}, {:fuzz, 300, 120_000}] do
    @tag [{variant, true}]
    @tag fuzz_id: "systems_plugin",
         contracts: ["PLUG-001"],
         contract_cases: ["PLUG-001/order", "PLUG-001/ownership", "PLUG-001/callback-failure"]
    @tag timeout: 180_000
    test "Plugin state and inputs follow an independent history (#{variant})", %{jido: jido} do
      options = [
        fuzz: unquote(variant) == :fuzz,
        max_runs: unquote(runs),
        max_run_time: unquote(milliseconds),
        max_shrinking_steps: 100,
        timeout: 180_000,
        contracts: ["PLUG-001"],
        contract_cases: ["PLUG-001/order", "PLUG-001/ownership", "PLUG-001/callback-failure"],
        examples: plugin_examples()
      ]

      Fuzz.check("systems_plugin", plugin_inputs(), options, &plugin_attempt(&1, jido))
    end

    @tag [{variant, true}]
    @tag fuzz_id: "systems_persistence",
         contracts: ["PERS-001"],
         contract_cases: [
           "PERS-001/roundtrip",
           "PERS-001/identity",
           "PERS-001/version",
           "PERS-001/portable"
         ]
    @tag timeout: 180_000
    test "Persistence validates complete state and saved records (#{variant})" do
      options = [
        fuzz: unquote(variant) == :fuzz,
        max_runs: unquote(runs),
        max_run_time: unquote(milliseconds),
        max_shrinking_steps: 100,
        timeout: 180_000,
        contracts: ["PERS-001"],
        contract_cases: [
          "PERS-001/roundtrip",
          "PERS-001/identity",
          "PERS-001/version",
          "PERS-001/portable"
        ],
        examples:
          for(
            mode <- ["identity", "version", "portable", "incomplete"],
            do: %{"value" => 4, "revision" => 2, "mode" => mode}
          )
      ]

      Fuzz.check("systems_persistence", persistence_inputs(), options, &persistence_attempt/1)
    end

    @tag [{variant, true}]
    @tag fuzz_id: "systems_topology",
         contracts: ["TOPO-001"],
         contract_cases: [
           "TOPO-001/unchanged",
           "TOPO-001/add",
           "TOPO-001/type-change",
           "TOPO-001/remove"
         ]
    @tag timeout: 180_000
    test "Topology update keeps exact existing specs (#{variant})", %{jido: jido} do
      options = [
        fuzz: unquote(variant) == :fuzz,
        max_runs: unquote(runs),
        max_run_time: unquote(milliseconds),
        max_shrinking_steps: 100,
        timeout: 180_000,
        contracts: ["TOPO-001"],
        contract_cases: [
          "TOPO-001/unchanged",
          "TOPO-001/add",
          "TOPO-001/type-change",
          "TOPO-001/remove"
        ],
        examples:
          for(
            mode <- ["unchanged", "add", "type-change", "remove"],
            do: %{"value" => 1, "count" => 2, "mode" => mode}
          )
      ]

      Fuzz.check("systems_topology", topology_inputs(), options, &topology_attempt(&1, jido))
    end
  end

  defp plugin_inputs do
    StreamData.fixed_map(%{
      "reverse" => StreamData.boolean(),
      "steps" =>
        StreamData.list_of(
          StreamData.fixed_map(%{
            "mode" =>
              StreamData.member_of([
                "ok",
                "tamper",
                "prepare_error",
                "reduce_error",
                "raise",
                "nonportable"
              ]),
            "amount" => StreamData.integer(-20..20)
          }),
          min_length: 1,
          max_length: 6
        )
    })
  end

  defp plugin_examples do
    for reverse <- [false, true] do
      %{
        "reverse" => reverse,
        "steps" =>
          Enum.map(
            ["ok", "tamper", "prepare_error", "reduce_error", "raise", "nonportable", "ok"],
            &%{"mode" => &1, "amount" => 2}
          )
      }
    end
  end

  defp plugin_attempt(input, jido) do
    packages = if input["reverse"], do: [Second, First], else: [First, Second]
    agent = %{PluginAgent.new!(id: unique_id("property-plugin")) | plugins: packages, vsn: nil}
    {:ok, server} = Jido.start_agent(jido, agent)

    try do
      expected = %{value: 0, prepared: [], marker: "", first: 0, second: 0}
      forged = signal("property.systems.change", %{mode: "ok", amount: 9})

      assert {:error, %Jido.Error.ValidationError{}} =
               Server.call(server, forged, context: %{plugin_inputs: %{First => :forged}})

      assert %{agent: unchanged, state_version: 0} = Server.snapshot(server)
      assert unchanged.state === expected

      _final_model =
        Enum.reduce(input["steps"], {expected, 0}, fn step, {state, revision} ->
          signal =
            signal("property.systems.change", %{mode: step["mode"], amount: step["amount"]})

          result = Server.call(server, signal)

          if step["mode"] == "ok" do
            first = state.first + step["amount"]
            second = if input["reverse"], do: state.first, else: first

            next = %{
              value: state.value + step["amount"],
              prepared: [state.value, state.value],
              marker: "second",
              first: first,
              second: second
            }

            assert {:ok, returned} = result
            assert returned.state === next
            assert %{agent: committed, state_version: version} = Server.snapshot(server)
            assert committed.state === next
            assert version == revision + 1
            {next, revision + 1}
          else
            assert {:error, reason} = result

            case step["mode"] do
              "prepare_error" -> assert reason == :prepare_denied
              "reduce_error" -> assert reason == :reduce_denied
              "tamper" -> assert Jido.Error.code(reason) == :plugin_state_owner_violation
              "raise" -> assert Jido.Error.code(reason) == :plugin_callback_failed
              "nonportable" -> assert Jido.Error.code(reason) == :non_portable_term
            end

            assert %{agent: committed, state_version: version} = Server.snapshot(server)
            assert committed.state === state
            assert version == revision
            {state, revision}
          end
        end)

      [
        "package-inputs",
        "reserved-input-rejected",
        "declaration-order",
        "owned-state",
        "failure-preserves-commit"
      ]
    after
      stop_agent(jido, server)
    end
  end

  defp persistence_inputs do
    StreamData.fixed_map(%{
      "value" => StreamData.integer(-100..100),
      "revision" => StreamData.integer(1..20),
      "mode" => StreamData.member_of(["identity", "version", "portable", "incomplete"])
    })
  end

  defp persistence_attempt(input) do
    path = Path.join(System.tmp_dir!(), unique_id("jido-property-persistence"))
    config = {Jido.Persistence.File, path: path}
    id = unique_id("property-record")
    opts = [namespace: "property/systems", partition: "blue", revision: input["revision"]]
    state = %{value: input["value"]}
    agent = StateAgent.new!(id: id, state: state)
    ref = Jido.Agent.Ref.new!(namespace: "property/systems", partition: "blue", id: id)
    key = Persistence.agent_key(ref)

    try do
      assert :ok = Persistence.save_agent(config, agent, opts)

      assert {:ok, restored, version} =
               Persistence.load_agent_with_revision(config, StateAgent, id, opts)

      assert restored.id == id
      assert restored.module == StateAgent
      assert restored.state === state
      assert version == input["revision"]
      assert :ok = Persistence.save_agent(config, agent, opts)
      assert {:ok, bytes} = Jido.Persistence.File.get(key, path: path)
      changed = %{agent | state: %{value: input["value"] + 1}}
      stale = opts ++ [expected_revision: input["revision"] - 1]
      assert {:error, :conflict} = Persistence.save_agent(config, changed, stale)
      assert {:ok, ^bytes} = Jido.Persistence.File.get(key, path: path)

      record = :erlang.binary_to_term(bytes, [:safe])

      case input["mode"] do
        "identity" ->
          assert :ok =
                   Jido.Persistence.File.put(
                     key,
                     :erlang.term_to_binary(%{record | partition: "red"}),
                     path: path
                   )

          assert {:error, {:invalid_persistence_record, :partition}} =
                   Persistence.load_agent(config, StateAgent, id, opts)

        "version" ->
          assert :ok =
                   Jido.Persistence.File.put(
                     key,
                     :erlang.term_to_binary(%{record | revision: -1}),
                     path: path
                   )

          assert {:error, {:invalid_persistence_record, :revision}} =
                   Persistence.load_agent(config, StateAgent, id, opts)

        mode ->
          invalid =
            if mode == "portable",
              do: %{agent | state: %{value: %{nested: <<1::1>>}}},
              else: %{agent | state: %{}}

          assert {:error, _} = Persistence.save_agent(config, invalid, opts)
          assert {:ok, ^bytes} = Jido.Persistence.File.get(key, path: path)
      end

      assert :ok = Jido.Persistence.File.put(key, bytes, path: path)

      assert {:ok, recovered, recovered_version} =
               Persistence.load_agent_with_revision(config, StateAgent, id, opts)

      assert recovered.state === state
      assert recovered_version == input["revision"]
      assert :ok = Persistence.delete_agent(config, StateAgent, id, opts)
      assert {:error, :deleted} = Persistence.load_agent(config, StateAgent, id, opts)

      [
        "roundtrip",
        "unchanged-write",
        "stale-write",
        "recover-after-corruption",
        "tombstone",
        input["mode"]
      ]
    after
      File.rm_rf!(path)
    end
  end

  defp topology_inputs do
    StreamData.fixed_map(%{
      "value" => StreamData.integer(-50..50),
      "count" => StreamData.integer(1..3),
      "mode" => StreamData.member_of(["unchanged", "add", "type-change", "remove"])
    })
  end

  defp topology_attempt(input, jido) do
    id = unique_id("property-topology")
    count = input["count"]
    initial = topology(id, count, input["value"])
    {:ok, controller} = Controller.start_link(jido: jido, topology: initial, repair: :manual)

    try do
      assert :ok = Controller.await_ready(controller)
      original = for index <- 1..count, do: Controller.whereis_agent(controller, :members, index)
      assert Enum.all?(original, &is_pid/1)
      before = Enum.map(original, &Server.snapshot/1)

      for snapshot <- before do
        assert snapshot.agent.state === %{value: input["value"]}
        assert snapshot.state_version == 0
      end

      {target_count, target_value, accepted?} =
        case input["mode"] do
          "unchanged" -> {count, input["value"], true}
          "add" -> {count + 1, input["value"], true}
          "type-change" -> {count, input["value"] / 1, false}
          "remove" -> {count - 1, input["value"], false}
        end

      target = topology(id, target_count, target_value)

      if accepted? do
        assert :ok = Controller.update(controller, target)
        assert :ok = Controller.await_ready(controller)
        assert Controller.status(controller).agents == target_count

        for index <- 1..target_count,
            do: assert(is_pid(Controller.whereis_agent(controller, :members, index)))
      else
        assert {:error, %Jido.Error.ValidationError{}} = Controller.update(controller, target)
        assert Controller.status(controller).agents == count
      end

      assert for(index <- 1..count, do: Controller.whereis_agent(controller, :members, index)) ==
               original

      assert Enum.map(original, &Server.snapshot/1) === before
      [input["mode"], "original-members-retained"]
    after
      stop_controller(jido, controller, id)
    end
  end

  defp topology(id, count, value) do
    definition =
      Jido.Topology.new!(
        name: "property-systems",
        groups: [%{key: :members, module: Member, count: count, initial_state: %{value: value}}]
      )

    Jido.Topology.instantiate(definition, id: id) |> Jido.Topology.unwrap!()
  end

  defp stop_agent(jido, server) do
    ref = Process.monitor(server)
    _ = Jido.stop_agent(jido, server)
    assert_receive {:DOWN, ^ref, :process, ^server, _}, 5_000
  end

  defp stop_controller(jido, controller, id) do
    owner = GenServer.whereis(Controller.name(jido, id, :owner))
    ref = if is_pid(owner), do: Process.monitor(owner)
    Supervisor.stop(controller)
    if ref, do: assert_receive({:DOWN, ^ref, :process, ^owner, _}, 5_000)
  end
end
