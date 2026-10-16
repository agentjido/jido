defmodule JidoTest.Contract.TopologyPlanningTest do
  use Covenant.Case, component: "jido.topology", async: false

  alias Jido.{Agent, Topology}
  alias Jido.Error.ValidationError
  alias Jido.Topology.{Plan, Ref, Reference}
  alias JidoTest.TopologyContract, as: T

  @tag obligation: "jido.topology.I15"
  test "entry lists reject invalid containers and improper tails with their field path" do
    for field <- [
          :agents,
          :groups,
          :resources,
          :relationships,
          :connections,
          :imports,
          :exports,
          :includes
        ] do
      assert {:error, %ValidationError{} = error} =
               Topology.new(%{field => :invalid, :name => "invalid"})

      assert error.message == "Expected a proper list"
      assert error.details.source_path == [field]
    end

    assert {:error, %ValidationError{} = error} =
             Topology.new(
               name: "invalid",
               agents: [%{key: :worker, definition: T.worker()} | :tail]
             )

    assert error.message == "Expected a proper list"
    assert error.details.source_path == [:agents]
  end

  @tag obligation: ["jido.topology.I6", "jido.topology.I9", "jido.topology.I14"]
  test "one planning operation resolves current contracts once and validates each member" do
    attrs = [
      name: "resolved",
      agents: [%{key: :leader, module: T.ObservedAgent}],
      groups: [
        %{
          key: :workers,
          module: T.ObservedAgent,
          count: 3,
          initial_state: %{count: Reference.member(:index)}
        }
      ],
      includes: [
        %{
          key: :included,
          topology: [name: "included", agents: [%{key: :worker, module: T.ObservedAgent}]]
        }
      ]
    ]

    assert {:ok, instance} = Topology.instantiate(attrs, id: "resolved")
    assert_receive :read_planning_agent
    assert_receive :read_planning_plugin
    refute_received :read_planning_agent
    refute_received :read_planning_plugin
    assert map_size(instance.plan.agents) == 5

    for index <- 1..3,
        do:
          assert(instance.plan.agents["group/workers/#{index}"].initial_state == %{count: index})

    assert map_size(instance.plan.resources) == 3

    assert {:ok, ^instance} = Topology.instantiate(attrs, id: "resolved")
    assert_receive :read_planning_agent
    assert_receive :read_planning_plugin
    refute_received :read_planning_agent
    refute_received :read_planning_plugin

    invalid =
      Keyword.put(attrs, :groups, [
        %{key: :workers, module: T.ObservedAgent, count: 3, initial_state: %{count: "invalid"}}
      ])

    assert {:error, %ValidationError{}} = Topology.instantiate(invalid, id: "invalid")
  end

  @tag obligation: ["jido.topology.I8", "jido.topology.I14", "jido.topology.I15"]
  test "input defaults preserve explicit false and zero and failed planning leaves the source reusable" do
    definition =
      Topology.new!(
        name: "input",
        schema:
          Zoi.object(%{
            count: Zoi.integer() |> Zoi.default(2),
            enabled: Zoi.boolean() |> Zoi.default(true)
          }),
        groups: [
          %{
            key: :workers,
            definition: T.worker(),
            count: Reference.input(:count),
            initial_state: %{count: Reference.member(:index), enabled: Reference.input(:enabled)}
          }
        ]
      )

    assert {:ok, default} = Topology.instantiate(definition, id: "defaults")
    assert default.input === %{count: 2, enabled: true}
    assert default.plan.agents["group/workers/2"].initial_state === %{count: 2, enabled: true}

    assert {:ok, empty} =
             Topology.instantiate(definition, id: "empty", input: %{count: 0, enabled: false})

    assert empty.input === %{count: 0, enabled: false}
    assert empty.plan.agents === %{}
    assert empty.plan.layers === []

    assert {:error, %ValidationError{}} =
             Topology.instantiate(definition, id: "bad", input: %{count: -1})

    assert {:error, %ValidationError{}} =
             Topology.instantiate(definition, id: "bad", input: %{enabled: "false"})

    assert {:ok, ^default} = Topology.instantiate(definition, id: "defaults")
    assert default.definition === definition
    assert {:ok, other} = Topology.instantiate(definition, id: "other")
    assert other.plan.agents["group/workers/1"].id != default.plan.agents["group/workers/1"].id
  end

  @tag obligation: ["jido.topology.I8", "jido.topology.I9", "jido.topology.I14"]
  test "member initialization checks defaults and refinements and keeps authored state" do
    worker =
      Agent.new!(
        name: "defaults",
        schema: Zoi.object(%{required: Zoi.map() |> Zoi.default(%{a: 1, b: 2})}),
        plugins: [JidoTest.AgentContract.First]
      )

    assert {:ok, instance} =
             Topology.instantiate(
               [
                 name: "defaults",
                 agents: [
                   %{key: :worker, definition: worker, initial_state: %{required: %{a: 9}}}
                 ]
               ],
               id: "defaults"
             )

    member = instance.plan.agents["agent/worker"]
    assert member.module === Agent
    assert member.definition === worker
    assert member.initial_state === %{required: %{a: 9}}

    assert Agent.instantiate!(worker, state: member.initial_state).state ===
             %{required: %{a: 9, b: 2}, first: 0}

    for {field, state} <- [
          {Zoi.integer() |> Zoi.default("invalid"), %{}},
          {Zoi.integer() |> Zoi.min(1) |> Zoi.default(0), %{}},
          {Zoi.integer() |> Zoi.refine({JidoTest.AgentContract, :changed_refinement, []}),
           %{value: 1}}
        ] do
      worker = Agent.new!(name: "invalid_initialization", schema: Zoi.object(%{value: field}))

      definition =
        Topology.new!(
          name: "invalid",
          agents: [%{key: :worker, definition: worker, initial_state: state}]
        )

      assert {:error, %ValidationError{subject: :state}} =
               Topology.instantiate(definition, id: "invalid")
    end
  end

  @tag obligation: ["jido.topology.I9", "jido.topology.I15"]
  test "members require one current module or neutral Agent definition and valid resolved state" do
    source = T.worker()

    for entry <- [
          %{key: :worker},
          %{key: :worker, module: JidoTest.AgentFixtures.CounterAgent, definition: source},
          %{key: :worker, definition: Agent.instantiate!(source)},
          %{key: :worker, module: String},
          %{key: :worker, definition: %{source | schema: :invalid}}
        ] do
      assert {:error, %ValidationError{}} = Topology.new(name: "source", agents: [entry])
    end

    definition =
      Topology.new!(
        name: "source",
        schema: Zoi.object(%{count: Zoi.any()}),
        agents: [
          %{key: :worker, definition: source, initial_state: %{count: Reference.input(:count)}}
        ]
      )

    assert {:error, %ValidationError{}} =
             Topology.instantiate(definition, id: "bad", input: %{count: "bad"})

    assert {:ok, instance} = Topology.instantiate(definition, id: "good", input: %{count: 3})
    assert instance.plan.agents["agent/worker"].definition === source
    assert instance.plan.agents["agent/worker"].initial_state === %{count: 3}
  end

  @tag obligation: [
         "jido.topology.I7",
         "jido.topology.I12",
         "jido.topology.I15",
         "jido.topology.I17"
       ]
  test "nested forms return canonical definitions and supplied structs are revalidated" do
    leaf = %{name: :leaf, agents: [%{key: :worker, definition: T.worker()}]}

    attrs = %{
      name: :canonical,
      includes: [%{key: :included, topology: leaf}],
      children: [%{key: :child, topology: Map.to_list(leaf)}]
    }

    assert {:ok, %Topology{} = definition} = Topology.new(attrs)
    assert [%{topology: %Topology{} = included}] = definition.includes
    assert [%{topology: %Topology{} = child}] = definition.children
    assert included === child
    assert included === Topology.new!(leaf)
    assert {:ok, ^definition} = Topology.new(Map.to_list(attrs))
    assert {:ok, ^definition} = Topology.new(definition)
    assert {:ok, instance} = Topology.instantiate(attrs, id: "canonical")
    assert instance.definition === definition
    assert {:ok, ^instance} = Topology.instantiate(definition, id: "canonical")

    for field <- [:includes, :children] do
      [entry] = Map.fetch!(definition, field)
      invalid = Map.put(definition, field, [%{entry | topology: %{entry.topology | name: nil}}])
      assert {:error, %ValidationError{} = expected} = Topology.new(invalid)
      assert Enum.take(expected.details.source_path, 2) == [field, 0]

      assert {:error, %ValidationError{} = actual} =
               Topology.instantiate(invalid, id: "invalid")

      assert actual.message == expected.message
      assert actual.details == expected.details
    end
  end

  @tag obligation: ["jido.topology.I10", "jido.topology.I11"]
  test "counted groups, ownership, subscriptions, and empty dependencies produce exact layers" do
    definition =
      Topology.new!(
        name: "graph",
        agents: [
          %{key: :leader, definition: T.worker()},
          %{key: :ready, definition: T.worker()}
        ],
        groups: [
          %{
            key: :workers,
            definition: T.worker(),
            count: 2,
            initial_state: %{count: Reference.member(:index)},
            depends_on: [:ready, :events, :leader, :ready]
          }
        ],
        resources: [%{key: :events}, %{key: :audit}],
        relationships: [%{parent: :leader, child: :workers, on_parent_exit: :continue}],
        connections: [
          %{agent: :workers, to: :events, path: "contract.**"},
          %{agent: :workers, to: :audit, path: "audit.**"},
          %{agent: :workers, to: :events, path: "other.**"}
        ]
      )

    assert {:ok, instance} = Topology.instantiate(definition, id: "root/a")

    assert instance.plan.layers === [
             ["agent/leader", "agent/ready", "bus/audit", "bus/events"],
             ["group/workers/1", "group/workers/2"]
           ]

    for index <- 1..2 do
      spec = instance.plan.agents["group/workers/#{index}"]
      assert spec.id === "root%2Fa/group/workers/#{index}"
      assert spec.initial_state === %{count: index}
      assert spec.parent === "agent/leader"
      assert spec.on_parent_exit === :continue
      assert spec.depends_on === ["agent/leader", "agent/ready", "bus/events", "bus/audit"]

      assert spec.subscriptions === [
               %{bus: "bus/events", path: "contract.**"},
               %{bus: "bus/audit", path: "audit.**"},
               %{bus: "bus/events", path: "other.**"}
             ]

      assert spec.node === node()
    end

    empty =
      Topology.new!(
        name: "empty",
        groups: [%{key: :empty, definition: T.worker(), count: 0}],
        agents: [%{key: :after, definition: T.worker(), depends_on: [:empty]}]
      )

    assert {:ok, %{plan: %{layers: [["agent/after"]]}}} = Topology.instantiate(empty, id: "empty")
  end

  @tag obligation: "jido.topology.I10"
  test "keyed groups sort stable escaped identities and reject duplicate or absent member keys" do
    definition =
      Topology.new!(
        name: "keyed",
        schema: Zoi.object(%{members: Zoi.any()}),
        groups: [
          %{
            key: :workers,
            definition: T.worker(),
            members: Reference.input(:members),
            key_by: :key,
            initial_state: %{label: Reference.member(:label)}
          }
        ]
      )

    members = [%{key: "z", label: "last"}, %{key: "a/b", label: "first"}]
    assert {:ok, first} = Topology.instantiate(definition, id: "keys", input: %{members: members})

    assert {:ok, second} =
             Topology.instantiate(definition,
               id: "keys",
               input: %{members: Enum.reverse(members)}
             )

    assert second.plan === first.plan
    assert first.plan.layers === [["group/workers/a%2Fb", "group/workers/z"]]
    assert first.plan.agents["group/workers/a%2Fb"].initial_state === %{label: "first"}

    for invalid <- [[hd(members), hd(members)], [%{label: "missing"}], :invalid] do
      assert {:error, %ValidationError{}} =
               Topology.instantiate(definition, id: "keys", input: %{members: invalid})
    end

    assert Plan.agent_key("a/b") != Plan.agent_key("a", "b")
    assert Plan.agent_key("a/b", "c") != Plan.agent_key("a", "b/c")
    assert Plan.agent_key("same") != Plan.bus_key("same")
  end

  @tag obligation: ["jido.topology.I10", "jido.topology.I11", "jido.topology.I15"]
  test "invalid sizes, graph cycles, missing endpoints, and duplicate owners fail before planning" do
    base = %{
      name: "invalid",
      agents: [
        %{key: :one, definition: T.worker()},
        %{key: :two, definition: T.worker()},
        %{key: :three, definition: T.worker()}
      ]
    }

    for attrs <- [
          %{base | agents: base.agents ++ [hd(base.agents)]},
          Map.put(base, :relationships, [%{parent: :missing, child: :one}]),
          Map.put(base, :relationships, [
            %{parent: :one, child: :two},
            %{parent: :two, child: :one}
          ]),
          Map.put(base, :connections, [%{agent: :one, to: :missing, path: "**"}]),
          Map.put(base, :relationships, [
            %{parent: :one, child: :two},
            %{parent: :one, child: :two}
          ]),
          Map.put(base, :relationships, [
            %{parent: :one, child: :three},
            %{parent: :two, child: :three}
          ]),
          %{
            base
            | agents: [
                %{key: :one, definition: T.worker(), depends_on: [:two]},
                %{key: :two, definition: T.worker(), depends_on: [:one]}
              ]
          }
        ] do
      assert {:error, %ValidationError{}} = Topology.new(attrs)
      assert {:error, %ValidationError{}} = Topology.instantiate(attrs, id: "bad")
    end

    ownership =
      Map.put(base, :relationships, [
        %{parent: :one, child: :three},
        %{parent: :two, child: :three}
      ])

    subscription = Map.put(base, :connections, [%{agent: :one, to: :missing, path: "**"}])
    both = Map.merge(ownership, Map.take(subscription, [:connections]))
    assert {:error, %ValidationError{} = expected} = Topology.new(ownership)
    assert {:error, %ValidationError{} = other} = Topology.new(subscription)
    refute {expected.message, expected.details} == {other.message, other.details}

    for result <- [Topology.new(both), Topology.instantiate(both, id: "invalid")] do
      assert {:error, %ValidationError{} = actual} = result
      assert actual.message == expected.message
      assert actual.details == expected.details
    end

    attrs = %{
      name: "limit",
      schema: Zoi.object(%{count: Zoi.integer()}),
      groups: [%{key: :workers, definition: T.worker(), count: Reference.input(:count)}],
      startup: %{max_agents: 2}
    }

    assert {:ok, at_limit} = Topology.instantiate(attrs, id: "limit", input: %{count: 2})
    assert map_size(at_limit.plan.agents) == 2

    for count <- [-1, 3] do
      assert {:error, %ValidationError{}} =
               Topology.instantiate(attrs, id: "limit", input: %{count: count})
    end
  end

  @tag obligation: ["jido.topology.I11", "jido.topology.I15"]
  test "exact placement is retained and remote Agents cannot use a local Bus" do
    remote = :"worker@127.0.0.1"
    attrs = %{name: "placement", agents: [%{key: :worker, definition: T.worker(), node: remote}]}
    assert {:ok, instance} = Topology.instantiate(attrs, id: "placed")
    assert instance.plan.agents["agent/worker"].node === remote

    connected =
      Map.merge(attrs, %{
        resources: [%{key: :events}],
        connections: [%{agent: :worker, to: :events, path: "contract.**"}]
      })

    assert {:ok, _} = Topology.new(connected)
    assert {:error, %ValidationError{}} = Topology.instantiate(connected, id: "remote")
  end

  @tag obligation: ["jido.topology.I10", "jido.topology.I12"]
  test "component counts include each subtree and retain empty and sibling scopes" do
    assert {:ok, instance} = Topology.instantiate(component_tree(), id: "components")

    assert instance.plan.components === %{
             [] => %{path: [], agents: 5, resources: 5},
             ["east"] => %{path: ["east"], agents: 3, resources: 2},
             ["east", "nested"] => %{path: ["east", "nested"], agents: 2, resources: 1},
             ["east", "empty"] => %{path: ["east", "empty"], agents: 0, resources: 0},
             ["west"] => %{path: ["west"], agents: 1, resources: 2}
           }

    assert map_size(instance.plan.agents) == 5
    assert map_size(instance.plan.resources) == 5
  end

  @tag obligation: ["jido.topology.I9", "jido.topology.I10", "jido.topology.I12"]
  test "nested limits reject excess members before member state validation" do
    branch = [:includes, Access.at(0), :topology]
    leaf = branch ++ [:includes, Access.at(0), :topology]

    invalid_state =
      put_in(component_tree(), leaf ++ [:groups, Access.at(0), :initial_state], %{count: "bad"})

    for {path, limit} <- [{branch, 2}, {leaf, 1}] do
      attrs = put_in(invalid_state, path ++ [:startup, :max_agents], limit)
      assert {:error, %ValidationError{} = error} = Topology.instantiate(attrs, id: "limit")
      assert error.message == "Topology exceeds startup.max_agents"
    end

    assert {:error, %ValidationError{} = error} =
             Topology.instantiate(invalid_state, id: "state")

    assert error.message == "Agent state does not match its schema"
  end

  @tag obligation: ["jido.topology.I12", "jido.topology.I14"]
  test "repeated includes isolate input and identity while sharing only declared Bus bindings" do
    team =
      Topology.new!(
        name: "team",
        schema: Zoi.object(%{label: Zoi.string()}),
        agents: [
          %{
            key: :worker,
            definition: T.worker(),
            initial_state: %{label: Reference.input(:label)}
          }
        ],
        imports: [%{key: :events, kind: :bus}],
        exports: [%{key: :public, kind: :agent, from: :worker}],
        connections: [%{agent: :worker, to: :events, path: "contract.**"}]
      )

    includes =
      for key <- [:east, :west],
          do: %{
            key: key,
            topology: team,
            inputs: %{label: Atom.to_string(key)},
            bindings: %{events: :events}
          }

    root = Topology.new!(name: "root", resources: [%{key: :events}], includes: includes)
    assert {:ok, instance} = Topology.instantiate(root, id: "root")
    east = instance.plan.agents["component/east/agent/worker"]
    west = instance.plan.agents["component/west/agent/worker"]
    assert east.id != west.id
    assert east.initial_state === %{label: "east"}
    assert west.initial_state === %{label: "west"}
    assert east.subscriptions === west.subscriptions
    assert east.subscriptions === [%{bus: "bus/events", path: "contract.**"}]
    assert map_size(instance.plan.resources) == 1
    assert Plan.resolve(instance.plan, Ref.ref(:east, :public), :agent) === east.key
    assert Plan.resolve(instance.plan, Ref.ref(:east, :worker), :agent) === nil
    assert Plan.resolve(instance.plan, Ref.ref(:east, :public), :bus) === nil

    assert {:error, %ValidationError{}} =
             Topology.instantiate(team, id: "unbound", input: %{label: "x"})

    assert {:error, %ValidationError{}} =
             Topology.new(name: "missing", includes: [%{key: :team, topology: team}])

    assert instance.definition === root
  end

  @tag obligation: ["jido.topology.I13", "jido.topology.I14"]
  test "Plugin contributions run Agent then group then Plugin order without changing saved declarations" do
    worker = T.worker([{T.Bus, [prefix: "inbox_"]}, {T.Audit, [prefix: "audit_"]}])

    definition =
      Topology.new!(
        name: "plugins",
        agents: [%{key: :first, definition: worker}],
        groups: [%{key: :workers, definition: worker, count: 2}]
      )

    assert {:ok, document, registry} = Topology.Codec.encode(definition)
    assert {:ok, instance} = Topology.instantiate(definition, id: "plugins")

    for {plugin, key} <- [
          {T.Bus, "first"},
          {T.Audit, "first"},
          {T.Bus, "workers"},
          {T.Audit, "workers"}
        ] do
      assert_receive {:contributed, ^plugin, ^key}
    end

    refute_received {:contributed, _, _}
    assert instance.definition === definition
    assert definition.resources === []
    assert {:ok, ^document} = Topology.Codec.encode(instance.definition, registry)

    for key <- ["agent/first", "group/workers/1", "group/workers/2"] do
      suffix = if key == "agent/first", do: "first", else: "workers"

      assert instance.plan.agents[key].subscriptions === [
               %{bus: "bus/inbox_#{suffix}", path: "contract.**"},
               %{bus: "bus/audit_#{suffix}", path: "contract.**"}
             ]
    end

    child = Topology.new!(name: "child", agents: [%{key: :worker, definition: worker}])

    assert {:ok, included} =
             Topology.instantiate(%{name: "root", includes: [%{key: :child, topology: child}]},
               id: "root"
             )

    assert included.plan.agents["component/child/agent/worker"].subscriptions === [
             %{bus: "component/child/bus/inbox_worker", path: "contract.**"},
             %{bus: "component/child/bus/audit_worker", path: "contract.**"}
           ]
  end

  @tag obligation: ["jido.topology.I13", "jido.topology.I15"]
  test "invalid Plugin contributions return structured errors and preserve application rejection reasons" do
    Process.put(:topology_contract_entries, [1 | :tail])

    for mode <- [:invalid, :owner, :entries, :improper, :raise, :throw, :exit] do
      definition =
        Topology.new!(
          name: "fault",
          agents: [%{key: :worker, definition: T.worker([{T.Bus, [mode: mode]}])}]
        )

      assert {:error, error} = Topology.instantiate(definition, id: "fault")
      assert byte_size(Exception.message(error)) > 0

      case mode do
        :raise ->
          assert %Jido.Error.ExecutionError{
                   details: %{
                     code: :plugin_callback_failed,
                     plugin: T.Bus,
                     callback: :contribute,
                     error: %ArgumentError{message: "contribution failure"}
                   }
                 } = error

        kind when kind in [:throw, :exit] ->
          assert %Jido.Error.ExecutionError{
                   details: %{
                     code: :plugin_callback_failed,
                     plugin: T.Bus,
                     callback: :contribute,
                     kind: ^kind,
                     reason: :contribution_failure
                   }
                 } = error

        mode when mode in [:invalid, :owner] ->
          assert %Jido.Error.ExecutionError{
                   details: %{
                     code: :plugin_invalid_callback_result,
                     plugin: T.Bus
                   }
                 } = error

        _ ->
          assert %ValidationError{} = error
      end
    end

    rejected =
      Topology.new!(
        name: "reject",
        agents: [%{key: :worker, definition: T.worker([{T.Bus, [mode: :reject]}])}]
      )

    assert {:error, :application_rejection} = Topology.instantiate(rejected, id: "rejected")

    conflict =
      Topology.new!(
        name: "conflict",
        agents: [%{key: :worker, definition: T.worker([T.Bus])}],
        resources: [%{key: :bus_worker}]
      )

    assert {:error, %ValidationError{}} = Topology.instantiate(conflict, id: "conflict")
  end

  @tag obligation: ["jido.topology.I13", "jido.topology.I15"]
  test "an included contribution collision fails before parent callbacks with its local path" do
    definition =
      Topology.new!(
        name: "root",
        agents: [%{key: :parent, definition: T.worker([T.Audit])}],
        includes: [
          %{
            key: :nested,
            topology: %{
              name: "nested",
              agents: [%{key: :worker, definition: T.worker([T.Bus])}],
              resources: [%{key: :bus_worker}]
            }
          }
        ]
      )

    assert {:error, %ValidationError{} = error} = Topology.instantiate(definition, id: "root")
    assert error.details.source_path === [:resources, 1, :key]
    assert_received {:contributed, T.Bus, "worker"}
    refute_received {:contributed, T.Audit, "parent"}
  end

  @tag obligation: ["jido.topology.I13", "jido.topology.I17"]
  test "all child event targets are checked before child contribution callbacks" do
    definition =
      Topology.new!(
        name: "parent",
        children: [
          %{
            key: :first,
            topology: %{
              name: "first",
              agents: [%{key: :worker, definition: T.worker([T.Bus])}]
            }
          },
          %{
            key: :second,
            topology: %{name: "second"},
            gate: %{events: ["public.**"], to: :missing}
          }
        ]
      )

    assert {:error, %ValidationError{}} = Topology.instantiate(definition, id: "parent")
    refute_received {:contributed, _, _}
  end

  @tag obligation: ["jido.topology.I13", "jido.topology.I15", "jido.topology.I17"]
  test "static child graphs and command targets are checked at every depth before parent contributions" do
    child = %{
      key: :leaf,
      topology: %{
        name: "leaf",
        agents: [%{key: :worker, definition: T.worker()}],
        exports: [%{key: :public, kind: :agent, from: :worker}],
        children: [%{key: :nested, topology: %{name: "nested"}}]
      },
      gate: %{
        commands: [
          %{type: "contract.run", member: :worker},
          %{type: "contract.child.run", member: {:child, :nested}}
        ]
      }
    }

    parent = [%{key: :parent, definition: T.worker([T.Audit])}]

    for depth <- 1..3 do
      attrs = child_tree(child, depth) |> Map.put(:agents, parent)
      assert {:ok, definition} = Topology.new(attrs)
      assert {:ok, _} = Topology.instantiate(definition, id: "valid")
      assert_received {:contributed, T.Audit, "parent"}

      for invalid <- [
            put_in(child.topology.exports, [%{key: :public, kind: :agent, from: :missing}]),
            put_in(child.gate.commands, [%{type: "contract.run", member: :missing}]),
            put_in(child.gate.commands, [%{type: "contract.run", member: {:child, :missing}}])
          ] do
        attrs = child_tree(invalid, depth) |> Map.put(:agents, parent)
        assert {:error, %ValidationError{} = error} = Topology.new(attrs)

        assert {:error, %ValidationError{} = planned_error} =
                 Topology.instantiate(attrs, id: "bad")

        assert planned_error.message == error.message
        refute_received {:contributed, _, _}
      end
    end
  end

  @tag obligation: ["jido.topology.I15", "jido.topology.I2"]
  test "public tuple and raising boundaries reject invalid fields, options, references, and runtime data" do
    for attrs <- [
          nil,
          %URI{},
          [name: "x", name: "y"],
          %{name: "bad", unknown: 1},
          %{name: "bad", agents: [1 | :tail]},
          %{name: "bad", metadata: %{pid: self()}},
          %{name: "bad", schema: Zoi.integer()}
        ] do
      assert {:error, %ValidationError{} = error} = Topology.new(attrs)
      assert byte_size(Exception.message(error)) > 0
      assert_raise error.__struct__, fn -> Topology.new!(attrs) end
    end

    for opts <- [[unknown: 1], [id: ""], [id: "x", input: []], [id: "x", input: %{pid: self()}]] do
      assert {:error, %ValidationError{}} =
               Topology.instantiate(%{name: "valid", schema: Zoi.map()}, opts)
    end

    missing = %{
      name: "missing",
      groups: [%{key: :workers, definition: T.worker(), count: Reference.input(:absent)}]
    }

    assert {:error, %ValidationError{}} = Topology.instantiate(missing, id: "missing")
  end

  @tag obligation: "jido.topology.I14"
  test "definition and planning operations do not spawn runtime processes" do
    owner = self()
    {tracer, monitor} = spawn_monitor(fn -> collect_spawns(owner, []) end)
    :erlang.trace(self(), true, [:procs, {:tracer, tracer}])

    try do
      definition = Topology.new!(name: "pure", agents: [%{key: :worker, definition: T.worker()}])
      assert {:ok, _} = Topology.instantiate(definition, id: "pure")
      assert {:ok, document, registry} = Topology.Codec.encode(definition)
      assert {:ok, _} = Topology.Codec.decode(document, registry, id: "decoded")
    after
      :erlang.trace(self(), false, [:procs])
      barrier = :erlang.trace_delivered(self())
      assert_receive {:trace_delivered, _, ^barrier}
      send(tracer, :finish)
    end

    assert_receive {:spawns, []}
    assert_receive {:DOWN, ^monitor, :process, ^tracer, :normal}
  end

  defp component_tree do
    worker = T.worker()

    leaf = %{
      name: "leaf",
      groups: [%{key: :workers, definition: worker, count: 2}],
      resources: [%{key: :events}],
      startup: %{max_agents: 2}
    }

    branch = %{
      name: "branch",
      agents: [%{key: :leader, definition: worker}],
      resources: [%{key: :events}],
      includes: [
        %{key: :nested, topology: leaf},
        %{
          key: :empty,
          topology: %{
            name: "empty",
            groups: [%{key: :workers, definition: worker, count: 0}]
          }
        }
      ],
      startup: %{max_agents: 3}
    }

    sibling = %{
      name: "sibling",
      agents: [%{key: :worker, definition: worker}],
      resources: [%{key: :first}, %{key: :second}],
      startup: %{max_agents: 1}
    }

    %{
      name: "components",
      agents: [%{key: :root, definition: worker}],
      resources: [%{key: :events}],
      includes: [%{key: :east, topology: branch}, %{key: :west, topology: sibling}],
      startup: %{max_agents: 5}
    }
  end

  defp child_tree(child, 1), do: %{name: "parent", children: [child]}

  defp child_tree(child, depth) do
    %{name: "parent", children: [%{key: :nested, topology: child_tree(child, depth - 1)}]}
  end

  defp collect_spawns(owner, spawns) do
    receive do
      {:trace, _, :spawn, _, _} = event -> collect_spawns(owner, [event | spawns])
      :finish -> send(owner, {:spawns, Enum.reverse(spawns)})
      _ -> collect_spawns(owner, spawns)
    end
  end
end
