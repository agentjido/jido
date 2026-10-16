defmodule JidoTest.Contract.TopologyAuthoringTest do
  use Covenant.Case, component: "jido.topology", async: false

  alias Jido.{Agent, Topology}
  alias JidoTest.AgentContract, as: A
  alias JidoTest.TopologyContract, as: T

  setup do
    previous = Code.compiler_options(debug_info: true)
    Process.register(self(), A.Observer)
    on_exit(fn -> Code.compiler_options(previous) end)
    :ok
  end

  @tag obligation: ["jido.topology.I1", "jido.topology.I3"]
  test "root Agent version and description do not become graph fields" do
    T.with_topology(
      "",
      fn module ->
        assert module.definition().name == "versioned"
        assert module.vsn() == 2
        assert module.definition().description == "owner description"
        assert %Topology{name: "versioned", agents: [], metadata: %{}} = module.topology()
        refute Map.has_key?(Map.from_struct(module.topology()), :vsn)
      end,
      ~s(name: "versioned", vsn: 2, description: "owner description")
    )
  end

  @tag obligation: ["jido.topology.I1", "jido.topology.I2", "jido.topology.I3"]
  test "a combined host retains the Agent API and separate constructor meanings" do
    T.with_topology(
      """
      agent do
        schema A.schema()
        metadata %{owner: true}
        plugin A.First
      end
      routes do
        signal_source "/topology"
        route "test.add", A.Add, as: :add
      end
      topology do
        schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(2)})
        metadata %{graph: true}
        agents do
          agent :worker, definition: T.worker()
        end
      end
      """,
      fn module ->
        for {name, arity} <- [
              definition: 0,
              owner: 0,
              vsn: 0,
              domain_schema: 0,
              complete_schema: 0,
              new_agent: 0,
              new_agent: 1,
              new_agent!: 0,
              new_agent!: 1,
              topology: 0,
              new: 1,
              new!: 1,
              cmd: 2,
              cmd: 3,
              route_action!: 1,
              add_signal: 1,
              add_signal: 2,
              child_spec: 1
            ],
            do: assert(function_exported?(module, name, arity))

        refute function_exported?(module, :new, 0)
        assert %Agent{id: nil, state: nil, module: ^module, vsn: 1} = module.definition()
        assert module.owner() === module.definition()
        assert module.vsn() == 1
        assert module.domain_schema() === A.schema()
        assert {:ok, complete} = Agent.complete_schema(module.definition())
        assert module.complete_schema() === complete
        assert module.definition().metadata === %{owner: true}
        assert module.topology().metadata === %{graph: true}

        assert {:ok, agent} = module.new_agent(id: "owner", state: %{count: 4})
        assert agent === module.new_agent!(id: "owner", state: %{count: 4})
        assert module.new_agent!().id != agent.id
        assert {:ok, %{state: %{count: 0, first: 0}}} = module.new_agent()
        assert {:ok, signal} = module.add_signal(%{amount: 3})
        assert signal.source == "/topology"

        assert {:ok, %{id: "owner", state: %{count: 7, first: 1}}, []} =
                 module.cmd(agent, signal, context: %{request: 1})

        assert {:ok, %{state: %{count: 7}}, []} = module.cmd(agent, signal)
        assert agent.state.count == 4

        assert {:ok, %Topology.Instance{input: %{count: 2}} = instance} = module.new(id: "graph")
        assert instance === module.new!(id: "graph")
        assert instance.definition === module.topology()
        assert instance.plan.agents["agent/worker"].initial_state === %{}
        assert {:error, error} = module.new(input: %{})
        assert_raise error.__struct__, fn -> module.new!(input: %{}) end
        assert {:error, error} = module.new_agent(id: "")
        assert_raise error.__struct__, fn -> module.new_agent!(id: "") end
      end
    )
  end

  @tag obligation: [
         "jido.topology.I1",
         "jido.topology.I2",
         "jido.topology.I3",
         "jido.topology.I17"
       ]
  test "optional blocks remain independent and only an explicit Agent selects a child director" do
    for {body, owner?} <- [{"", false}, {"agent do\nschema A.schema()\nend", true}] do
      T.with_topology(body, fn module ->
        assert %Agent{id: nil, state: nil} = module.definition()
        assert {:ok, %Agent{}} = module.new_agent()
        assert {:ok, %{plan: %{agents: agents, resources: resources}}} = module.new(id: "empty")
        assert agents === %{} and resources === %{}
        topology = module.topology()

        for field <- [
              :agents,
              :groups,
              :resources,
              :relationships,
              :connections,
              :includes,
              :imports,
              :exports,
              :children
            ],
            do: assert(Map.fetch!(topology, field) === [])

        root = Topology.new!(name: "root", children: [%{key: :child, topology: module}])
        assert [child] = root.children
        assert child.director === if(owner?, do: module.definition(), else: nil)
        assert {:ok, _} = Topology.instantiate(root, id: "root")
      end)
    end
  end

  @tag obligation: ["jido.topology.I4", "jido.topology.I5"]
  test "computed options and mixed extension callbacks evaluate once and retain their order" do
    T.with_topology(
      """
      agent do
        label :owner, "label"
      end
      topology do
        agents do
          agent :base, definition: T.worker()
          role :worker, T.worker()
        end
      end
      """,
      fn module ->
        assert_receive {:observed, :options}
        assert_receive {:observed, {:lowered, A.Labels}}
        assert_receive {:observed, {:lowered, :agent_dual}}
        assert_receive {:observed, {:lowered, :roles}}
        assert_receive {:observed, {:lowered, :topology_dual}}
        refute_received {:observed, _}
        assert module.definition().name == "computed"
        assert module.definition().description == "computed owner"
        assert module.vsn() == 3
        assert module.definition().metadata === %{owner: "label", dual: true}
        assert module.topology().metadata === %{order: [:roles, :dual]}
        assert Enum.map(module.topology().agents, & &1.key) == ["base", "worker"]
      end,
      "(A.observe(:options); [name: \"computed\", description: \"computed owner\", vsn: 3, " <>
        "extensions: [A.Labels, T.Roles, T.Dual]])"
    )
  end

  @tag obligation: ["jido.topology.I7", "jido.topology.I11", "jido.topology.I12"]
  test "core sections lower to their collections with include bindings and exports" do
    T.with_topology(
      """
      defmodule Included do
        use Jido.Topology, name: "included"
        topology do
          imports do
            bus :events
          end
          exports do
            bus :public_events, from: :events
          end
        end
      end
      topology do
        agents do
          agent :lead, definition: T.worker()
          group :workers, definition: T.worker(), count: 2
          agent :backup, definition: T.worker()
        end
        resources do
          bus :events
          bus :audit
        end
        relationships do
          owns :lead, :workers, on_parent_exit: :continue
        end
        connections do
          subscribe :workers, to: :events, path: "contract.**"
        end
        topologies do
          include :team, __MODULE__.Included do
            bind :events, to: :events
          end
        end
        exports do
          group :public_workers, from: :workers
        end
        startup do
          concurrency 2
          max_agents 4
          retry_interval 37
          task_timeout 211
        end
      end
      """,
      fn module ->
        definition = module.topology()
        assert [%{key: "lead"}, %{key: "backup"}] = definition.agents
        assert [%{key: "workers", count: 2}] = definition.groups
        assert [%{key: "events", kind: :bus}, %{key: "audit", kind: :bus}] = definition.resources

        assert [%{parent: "lead", child: "workers", on_parent_exit: :continue}] =
                 definition.relationships

        assert [%{agent: "workers", to: "events", path: "contract.**"}] = definition.connections
        assert [%{key: "public_workers", kind: :group, from: "workers"}] = definition.exports

        assert definition.startup === %{
                 concurrency: 2,
                 max_agents: 4,
                 retry_interval: 37,
                 task_timeout: 211
               }

        assert [%{key: "team", topology: included, bindings: [%{key: "events", to: "events"}]}] =
                 definition.includes

        assert [%{key: "events", kind: :bus}] = included.imports
        assert [%{key: "public_events", kind: :bus, from: "events"}] = included.exports
        assert {:ok, %{plan: plan}} = module.new(id: "collections")
        assert map_size(plan.agents) == 4
        assert map_size(plan.resources) == 2
        assert plan.agents["group/workers/1"].parent == "agent/lead"
      end
    )
  end

  @tag obligation: ["jido.topology.I4", "jido.topology.I7"]
  test "map, keyword, attribute options and caller scope produce the same graph" do
    for options <- ["[name: \"forms\"]", "%{name: \"forms\"}", "List.wrap(name: \"forms\")"] do
      T.with_topology(
        """
        alias Jido.Topology.Reference, as: R
        definition = T.worker()
        topology do
          schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(2)})
          agents do
            group :workers, definition: definition, count: R.input(:count)
          end
        end
        """,
        fn module ->
          expected =
            Topology.new!(
              name: "forms",
              schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(2)}),
              groups: [
                %{key: :workers, definition: T.worker(), count: Topology.Reference.input(:count)}
              ]
            )

          assert module.topology() === expected
          assert {:ok, document, registry} = Topology.Codec.encode(expected)

          assert {:ok, ^expected} =
                   Topology.Codec.decode(JSON.decode!(JSON.encode!(document)), registry)

          assert {:ok, instance} = module.new(id: "forms")
          assert {:ok, ^instance} = Topology.Codec.decode(document, registry, id: "forms")
        end,
        options
      )
    end

    T.with_topology(
      "",
      fn module ->
        assert module.definition().name == "attribute"
        assert module.topology().name == "attribute"
      end,
      "@options",
      "@options [name: \"attribute\"]"
    )
  end

  @tag obligation: ["jido.topology.I1", "jido.topology.I5"]
  test "keyword graph options and description are assigned to the correct definition" do
    T.with_topology(
      "agent do\nschema A.schema()\nmetadata %{owner: true}\nend",
      fn module ->
        assert module.definition().description === "owner description"
        assert module.definition().metadata === %{owner: true}
        assert module.domain_schema() === A.schema()
        assert module.topology().metadata === %{graph: true}
        assert [%{key: "worker"}] = module.topology().agents
        assert module.topology().startup.concurrency === 2
        assert {:ok, %{input: %{count: 4}}} = module.new(id: "keyword")
      end,
      "name: \"keyword\", description: \"owner description\", " <>
        "schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(4)}), " <>
        "metadata: %{graph: true}, agents: [%{key: :worker, definition: T.worker()}], " <>
        "startup: %{concurrency: 2}"
    )
  end

  @tag obligation: ["jido.topology.I1", "jido.topology.I5"]
  test "inline Actions retain route lookup, helpers, defaults, and direct execution" do
    T.with_topology(
      """
      agent do
        schema A.schema()
      end
      routes do
        signal_source "/inline-topology"
        route "test.inline", as: :inline, defaults: %{amount: 6} do
          action %{amount: amount}, schema: Zoi.object(%{amount: Zoi.integer()}), context: context do
            {:ok, %{context.agent_state | count: amount}}
          end
        end
      end
      """,
      fn module ->
        action = module.route_action!("test.inline")
        assert [%{target: {^action, %{amount: 6}}}] = module.definition().routes
        assert {:ok, signal} = module.inline_signal(%{})
        assert signal.data === %{}
        assert {:ok, %{state: %{count: 6}}, []} = module.cmd(module.new_agent!(), signal)
        assert {:error, _} = module.inline_signal([], [])
        assert {:error, _} = module.inline_signal(%{}, type: "other")
      end
    )
  end

  @tag obligation: ["jido.topology.I5", "jido.topology.I15"]
  test "invalid extension declarations and outputs fail at compilation" do
    for {options, body} <- [
          {"extensions: [T.Unclaimed]",
           "topology do\nagents do\nrole :worker, T.worker()\nend\nend"},
          {"extensions: [T.InvalidLowering]", ""},
          {"extensions: [T.Roles, T.Roles]", ""},
          {"extensions: [A.NoLowerExtension]", ""},
          {"name: \"duplicate\"", ""},
          {"unknown: true", ""},
          {"metadata: %{}", "topology do\nmetadata %{owner: true}\nend"}
        ] do
      error =
        assert_raise CompileError, fn ->
          T.with_topology(body, fn _ -> :ok end, "name: \"invalid\", #{options}")
        end

      assert Path.basename(error.file) == "authoring_fixture.ex"
      assert error.line > 0

      if options == "extensions: [T.Unclaimed]" do
        assert error.line == 8
      end
    end
  end

  @tag obligation: ["jido.topology.I3", "jido.topology.I15"]
  test "invalid sections, field presence, and dependencies retain authored source locations" do
    for body <- [
          "agent do\nschema Zoi.object(%{first: Zoi.integer()})\nplugin A.First\nend",
          "agent do\nend\nroutes do\nroute \"test.run\", String\nend",
          "routes do\nroute \"test.add\", A.Add\nend",
          "topology do\nagents do\ngroup :workers, definition: T.worker(), count: nil\nend\nend",
          "topology do\nagents do\nagent :worker, String\nend\nend",
          "topology do\nagents do\nagent :worker, definition: T.worker(), initial_state: self()\nend\nend"
        ] do
      error = assert_raise CompileError, fn -> T.with_topology(body, fn _ -> :ok end) end
      assert Path.basename(error.file) == "authoring_fixture.ex"
      assert error.line > 0, inspect({body, error})
      assert byte_size(error.description) > 0
    end

    assert_raise CompileError, fn ->
      T.with_topology("agents do\nagent :worker, definition: T.worker()\nend", fn _ -> :ok end)
    end

    T.with_topology(
      "topology do\nagents do\ngroup :workers, definition: T.worker()\nend\nend",
      fn module ->
        assert [%{count: 1}] = module.topology().groups
      end
    )
  end

  @tag obligation: ["jido.topology.I4", "jido.topology.I15"]
  test "schema failures in both root roles retain their authored locations" do
    for section <- [:agent, :topology],
        field <- [
          "Zoi.any() |> Zoi.default(fn -> :ok end)",
          "Zoi.integer() |> Zoi.refine(fn value -> {:ok, value} end)"
        ] do
      error =
        assert_raise Spark.Error.DslError, fn ->
          T.with_topology(
            "#{section} do\n  schema Zoi.object(%{value: #{field}})\nend",
            fn _ -> :ok end
          )
        end

      assert Exception.message(error) =~ "authoring_fixture.ex:6"
    end

    for section <- [:agent, :topology] do
      error =
        assert_raise CompileError, fn ->
          T.with_topology("#{section} do\n  schema Zoi.integer()\nend", fn _ -> :ok end)
        end

      assert Path.basename(error.file) == "authoring_fixture.ex"
      assert error.line == 7
    end
  end

  @tag obligation: ["jido.topology.I1", "jido.topology.I8", "jido.topology.I15"]
  test "static MFA schema rules retain validation in both root roles" do
    for section <- [:agent, :topology] do
      T.with_topology(
        """
        #{section} do
          schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(1) |> Zoi.refine({__MODULE__, :positive, []})})
        end
        def positive(value, _opts), do: if(value > 0, do: :ok, else: {:error, "must be positive"})
        """,
        fn module ->
          if section == :agent do
            assert module.new_agent!().state === %{value: 1}
            assert {:error, _} = module.new_agent(state: %{value: 0})
          else
            assert {:ok, %{input: %{value: 1}}} = module.new(id: "schema")
            assert {:error, _} = module.new(id: "schema", input: %{value: 0})
          end
        end
      )
    end
  end

  @tag obligation: "jido.topology.I6"
  test "the shared host and members reject a reloaded invalid Action contract" do
    T.with_topology(
      """
      defmodule Run do
        use Jido.Action, name: "topology_reload_action"
        def run(_, context), do: {:ok, context.agent_state}
      end
      agent do
      end
      routes do
        route "test.run", __MODULE__.Run
      end
      topology do
        agents do
          agent :worker, __MODULE__
        end
      end
      """,
      fn module ->
        assert {:ok, _} = module.new(id: "before")
        action = Module.concat(module, Run)
        previous = Code.compiler_options(ignore_module_conflict: true)

        try do
          Code.compile_string(
            "defmodule #{inspect(action)} do\ndef run(_, _), do: {:ok, %{}}\nend"
          )

          assert {:error, _} = module.new_agent()
          assert {:error, _} = module.new(id: "after")
          assert_raise Jido.Error.ValidationError, fn -> module.definition() end
        after
          Code.compiler_options(previous)
        end
      end
    )
  end

  @tag obligation: "jido.topology.I6"
  test "the shared host and member planning read current Plugin contracts after reload" do
    T.with_topology(
      """
      defmodule Owned do
        use Jido.Plugin
        def state_spec(_), do: {:owned, Zoi.integer() |> Zoi.default(1)}
      end
      agent do
        plugin __MODULE__.Owned
      end
      topology do
        agents do
          agent :worker, definition: Jido.Agent.new!(name: "owned", plugins: [__MODULE__.Owned])
        end
      end
      """,
      fn module ->
        plugin = Module.concat(module, Owned)
        assert module.new_agent!().state.owned == 1
        assert {:ok, _} = module.new(id: "before")
        previous = Code.compiler_options(ignore_module_conflict: true)

        try do
          Code.compile_string(
            "defmodule #{inspect(plugin)} do\nuse Jido.Plugin\ndef state_spec(_), do: {:owned, Zoi.integer() |> Zoi.default(2)}\nend"
          )

          assert module.new_agent!().state.owned == 2
          assert {:ok, %{owned: 2}} = Zoi.parse(module.complete_schema(), %{})

          Code.compile_string(
            "defmodule #{inspect(plugin)} do\nuse Jido.Plugin\ndef state_spec(_), do: {:owned, :invalid}\nend"
          )

          assert {:error, _} = module.new_agent()
          assert {:error, _} = module.new(id: "after")
          assert_raise Jido.Error.ValidationError, fn -> module.definition() end
        after
          Code.compiler_options(previous)
        end
      end
    )
  end
end
