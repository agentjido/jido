defmodule JidoTest.Authoring.Topology.Cases do
  @moduledoc false
  alias Jido.Topology.{Plan, Ref, Reference}
  alias JidoTest.Authoring.Topology.Fixtures

  # Expectations are authored separately from the DSL fixtures and planner.
  def spec(variant) when variant in [:minimal, :minimal_keyword] do
    %{
      id: "minimal",
      attrs: %{
        metadata: %{"suite" => "topology"},
        agents: [%{key: :worker, module: Fixtures.Worker, initial_state: %{label: "single"}}]
      },
      scenarios: [
        scenario(
          %{},
          plan(
            [agent("worker", %{label: "single"})],
            [],
            [["agent/worker"]],
            endpoints([{"worker", :agent}])
          )
        )
      ]
    }
  end

  def spec(:counted) do
    workers = for n <- 1..2, do: member(Integer.to_string(n), %{value: n})
    observer = agent("observer", %{}, depends_on: ["group/workers/1", "group/workers/2"])
    lookup = endpoints([{"observer", :agent}, {"workers", :group}])

    %{
      id: "counted",
      attrs: %{
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(2)}),
        agents: [%{key: :observer, module: Fixtures.Worker, depends_on: [:workers]}],
        groups: [
          %{
            key: :workers,
            module: Fixtures.Worker,
            count: Reference.input(:count),
            initial_state: %{value: Reference.member(:index)}
          }
        ],
        startup: %{max_agents: 3}
      },
      scenarios: [
        scenario(
          %{},
          plan(
            [observer | workers],
            [],
            [["group/workers/1", "group/workers/2"], ["agent/observer"]],
            lookup
          ),
          %{count: 2}
        ),
        scenario(%{count: 0}, plan([agent("observer")], [], [["agent/observer"]], lookup))
      ],
      invalid_inputs: [%{count: -1}, %{count: 3}, %{count: "two"}]
    }
  end

  def spec(:keyed) do
    members = [%{key: "a/b", label: "slash"}, %{key: "a%2Fb", label: "percent"}]

    expected =
      plan(
        [
          member("a/b", %{label: "slash"}, "a%2Fb"),
          member("a%2Fb", %{label: "percent"}, "a%252Fb")
        ],
        [],
        [["group/workers/a%252Fb", "group/workers/a%2Fb"]],
        endpoints([{"workers", :group}])
      )

    %{
      id: "keyed",
      attrs: %{
        schema:
          Zoi.object(%{members: Zoi.list(Zoi.object(%{key: Zoi.string(), label: Zoi.string()}))}),
        groups: [
          %{
            key: :workers,
            module: Fixtures.Worker,
            members: Reference.input(:members),
            key_by: :key,
            initial_state: %{label: Reference.member(:label)}
          }
        ]
      },
      scenarios: [
        scenario(%{members: members}, expected),
        scenario(%{members: Enum.reverse(members)}, expected),
        scenario(%{members: []}, plan([], [], [], endpoints([{"workers", :group}])))
      ],
      invalid_inputs: [
        %{},
        %{members: [hd(members), hd(members)]},
        %{members: [%{key: "x"}]},
        %{members: [%{key: "", label: "empty"}]}
      ]
    }
  end

  def spec(:ownership) do
    %{
      id: "ownership",
      attrs: %{
        agents: [
          %{key: :parent, module: Fixtures.Worker},
          %{key: :child, module: Fixtures.Worker},
          %{key: :observer, module: Fixtures.Worker, depends_on: [:child]}
        ],
        relationships: [%{parent: :parent, child: :child, on_parent_exit: :continue}]
      },
      scenarios: [
        scenario(
          %{},
          plan(
            [
              agent("parent"),
              agent("child", %{},
                parent: "agent/parent",
                depends_on: ["agent/parent"],
                on_parent_exit: :continue
              ),
              agent("observer", %{}, depends_on: ["agent/child"])
            ],
            [],
            [["agent/parent"], ["agent/child"], ["agent/observer"]],
            endpoints([{"parent", :agent}, {"child", :agent}, {"observer", :agent}])
          )
        )
      ]
    }
  end

  def spec(:bus) do
    %{
      id: "bus",
      attrs: %{
        agents: [%{key: :worker, module: Fixtures.Worker}],
        resources: [%{key: :events}],
        connections: [%{agent: :worker, to: :events, path: "authoring.work"}]
      },
      scenarios: [
        scenario(
          %{},
          plan(
            [
              agent("worker", %{},
                depends_on: ["bus/events"],
                subscriptions: [%{bus: "bus/events", path: "authoring.work"}]
              )
            ],
            [bus("events")],
            [["bus/events"], ["agent/worker"]],
            endpoints([{"worker", :agent}, {"events", :bus}])
          )
        )
      ]
    }
  end

  def spec(:nested) do
    %{
      id: "nested",
      attrs: %{
        schema: Zoi.object(%{label: Zoi.string() |> Zoi.default("nested")}),
        agents: [
          %{key: :observer, module: Fixtures.Worker, depends_on: [Ref.ref(:team, :public_worker)]}
        ],
        resources: [%{key: :events}],
        includes: [
          %{
            key: :team,
            topology: child_attrs(),
            inputs: %{label: Reference.input(:label)},
            bindings: %{events: :events}
          }
        ]
      },
      scenarios: [
        scenario(%{}, nested_plan("nested"), %{label: "nested"}),
        scenario(%{label: "override"}, nested_plan("override"))
      ],
      invalid_inputs: [%{label: 42}]
    }
  end

  def spec(:plugin) do
    agent_opts = [
      module: Fixtures.PluginWorker,
      depends_on: ["bus/inbox_solo"],
      subscriptions: [%{bus: "bus/inbox_solo", path: "authoring.work"}]
    ]

    member_opts = [
      module: Fixtures.PluginWorker,
      depends_on: ["bus/inbox_workers"],
      subscriptions: [%{bus: "bus/inbox_workers", path: "authoring.work"}]
    ]

    %{
      id: "plugin",
      attrs: %{
        agents: [%{key: :solo, module: Fixtures.PluginWorker}],
        groups: [%{key: :workers, module: Fixtures.PluginWorker, count: 2}]
      },
      scenarios: [
        scenario(
          %{},
          plan(
            [
              agent("solo", %{}, agent_opts),
              member("1", %{}, "1", member_opts),
              member("2", %{}, "2", member_opts)
            ],
            [bus("inbox_solo"), bus("inbox_workers")],
            [
              ["bus/inbox_solo", "bus/inbox_workers"],
              ["agent/solo", "group/workers/1", "group/workers/2"]
            ],
            endpoints([
              {"solo", :agent},
              {"workers", :group},
              {"inbox_solo", :bus},
              {"inbox_workers", :bus}
            ])
          )
        )
      ]
    }
  end

  def spec(:repeated) do
    %{
      id: "repeated",
      attrs: %{
        schema: Zoi.object(%{label: Zoi.string() |> Zoi.default("left")}),
        resources: [%{key: :events}],
        includes: [
          %{
            key: "team/a",
            topology: child_attrs(),
            inputs: %{label: Reference.input(:label)},
            bindings: %{events: :events}
          },
          %{
            key: "team%2Fa",
            topology: child_attrs(),
            inputs: %{label: "right"},
            bindings: %{events: :events}
          }
        ]
      },
      scenarios: [
        scenario(%{}, repeated_plan("left"), %{label: "left"}),
        scenario(%{label: "changed"}, repeated_plan("changed"))
      ],
      invalid_inputs: [%{label: false}]
    }
  end

  def spec(:deep) do
    %{
      id: "deep",
      attrs: %{
        schema:
          Zoi.object(%{
            count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(2),
            label: Zoi.string() |> Zoi.default("deep")
          }),
        agents: [
          %{
            key: :observer,
            module: Fixtures.Worker,
            depends_on: [Ref.ref(:region, :leader), Ref.ref(:region, :workers)]
          }
        ],
        resources: [%{key: :events}],
        connections: [
          %{agent: :observer, to: Ref.ref(:region, :events), path: "authoring.work"}
        ],
        includes: [
          %{
            key: :region,
            topology: region_attrs(),
            inputs: %{count: Reference.input(:count), label: Reference.input(:label)},
            bindings: %{events: :events}
          }
        ],
        startup: %{max_agents: 5}
      },
      references: %{
        "schemas/deep_leaf" => {:schema, leaf_attrs().schema},
        "schemas/deep_region" => {:schema, region_attrs().schema}
      },
      scenarios: [
        scenario(%{}, deep_plan(2, "deep"), %{count: 2, label: "deep"}),
        scenario(%{count: 0, label: "empty"}, deep_plan(0, "empty"))
      ],
      invalid_inputs: [%{count: -1}, %{count: 3}, %{count: "two"}, %{label: false}]
    }
  end

  def spec(:configured) do
    %{
      id: "configured",
      attrs: %{
        agents: [
          %{key: :parent, module: Fixtures.Worker},
          %{key: :orphan, module: Fixtures.Worker},
          %{key: :continued, module: Fixtures.Worker},
          %{key: :stopped, module: Fixtures.Worker},
          %{key: :remote, module: Fixtures.Worker, node: :"authoring@127.0.0.1"}
        ],
        resources: [%{key: :events, config: [max_log_size: 17]}],
        relationships: [
          %{parent: :parent, child: :orphan, on_parent_exit: :emit_orphan},
          %{parent: :parent, child: :continued, on_parent_exit: :continue},
          %{parent: :parent, child: :stopped, on_parent_exit: :stop}
        ],
        connections: [%{agent: :parent, to: :events, path: "authoring.work"}],
        startup: %{concurrency: 2, max_agents: 5, retry_interval: 37, task_timeout: 211}
      },
      references: %{
        "atoms/max_log_size" => {:atom, :max_log_size},
        "nodes/remote" => {:atom, :"authoring@127.0.0.1"}
      },
      scenarios: [
        scenario(
          %{},
          plan(
            [
              agent("parent", %{},
                depends_on: ["bus/events"],
                subscriptions: [%{bus: "bus/events", path: "authoring.work"}]
              ),
              agent("orphan", %{},
                parent: "agent/parent",
                depends_on: ["agent/parent"],
                on_parent_exit: :emit_orphan
              ),
              agent("continued", %{},
                parent: "agent/parent",
                depends_on: ["agent/parent"],
                on_parent_exit: :continue
              ),
              agent("stopped", %{}, parent: "agent/parent", depends_on: ["agent/parent"]),
              agent("remote", %{}, node: :"authoring@127.0.0.1")
            ],
            [Map.put(bus("events"), :config, max_log_size: 17)],
            [
              ["agent/remote", "bus/events"],
              ["agent/parent"],
              ["agent/continued", "agent/orphan", "agent/stopped"]
            ],
            endpoints([
              {"parent", :agent},
              {"orphan", :agent},
              {"continued", :agent},
              {"stopped", :agent},
              {"remote", :agent},
              {"events", :bus}
            ])
          )
        )
      ]
    }
  end

  def spec(:combined) do
    %{
      id: "combined",
      attrs: %{
        metadata: %{"kind" => "topology", :role_count => 1},
        agents: [%{key: :worker, module: Fixtures.Worker}]
      },
      scenarios: [
        scenario(
          %{},
          plan([agent("worker")], [], [["agent/worker"]], endpoints([{"worker", :agent}]))
        )
      ]
    }
  end

  def child_attrs do
    %{
      name: "authoring_child",
      schema: Zoi.object(%{label: Zoi.string()}),
      agents: [
        %{key: :worker, module: Fixtures.Worker, initial_state: %{label: Reference.input(:label)}}
      ],
      imports: [%{key: :events, kind: :bus}],
      connections: [%{agent: :worker, to: :events, path: "authoring.work"}],
      exports: [%{kind: :agent, key: :public_worker, from: :worker}]
    }
  end

  defp nested_plan(label) do
    child = "component/team/agent/worker"

    lookup =
      Map.put(
        endpoints([{"observer", :agent}, {"events", :bus}]),
        Ref.ref(:team, :public_worker),
        %{key: child, kind: :agent}
      )

    plan(
      [
        agent("worker", %{label: label},
          key: child,
          declaration: child,
          scope: ["team"],
          depends_on: ["bus/events"],
          subscriptions: [%{bus: "bus/events", path: "authoring.work"}]
        ),
        agent("observer", %{}, depends_on: [child])
      ],
      [bus("events")],
      [["bus/events"], [child], ["agent/observer"]],
      lookup,
      %{["team"] => %{path: ["team"], agents: 1, resources: 0}}
    )
  end

  defp repeated_plan(label) do
    first = "component/team%2Fa/agent/worker"
    second = "component/team%252Fa/agent/worker"

    plan(
      [
        agent("worker", %{label: label},
          key: first,
          declaration: first,
          scope: ["team/a"],
          depends_on: ["bus/events"],
          subscriptions: [%{bus: "bus/events", path: "authoring.work"}]
        ),
        agent("worker", %{label: "right"},
          key: second,
          declaration: second,
          scope: ["team%2Fa"],
          depends_on: ["bus/events"],
          subscriptions: [%{bus: "bus/events", path: "authoring.work"}]
        )
      ],
      [bus("events")],
      [["bus/events"], [second, first]],
      %{
        "events" => %{key: "bus/events", kind: :bus},
        Ref.ref("team/a", :public_worker) => %{key: first, kind: :agent},
        Ref.ref("team%2Fa", :public_worker) => %{key: second, kind: :agent}
      },
      %{
        ["team/a"] => %{path: ["team/a"], agents: 1, resources: 0},
        ["team%2Fa"] => %{path: ["team%2Fa"], agents: 1, resources: 0}
      }
    )
  end

  defp leaf_attrs do
    %{
      name: "authoring_deep_leaf",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.min(0), label: Zoi.string()}),
      agents: [
        %{key: :leader, module: Fixtures.Worker, initial_state: %{label: Reference.input(:label)}}
      ],
      groups: [
        %{
          key: :workers,
          module: Fixtures.Worker,
          count: Reference.input(:count),
          initial_state: %{label: Reference.input(:label), value: Reference.member(:index)},
          depends_on: [:leader]
        }
      ],
      imports: [%{key: :events, kind: :bus}],
      connections: [%{agent: :workers, to: :events, path: "authoring.work"}],
      exports: [
        %{kind: :agent, key: :leader, from: :leader},
        %{kind: :group, key: :workers, from: :workers},
        %{kind: :bus, key: :events, from: :events}
      ],
      startup: %{max_agents: 3}
    }
  end

  defp region_attrs do
    %{
      name: "authoring_deep_region",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(1),
          label: Zoi.string() |> Zoi.default("region")
        }),
      imports: [%{key: :events, kind: :bus}],
      includes: [
        %{
          key: :team,
          topology: leaf_attrs(),
          inputs: %{count: Reference.input(:count), label: Reference.input(:label)},
          bindings: %{events: :events}
        }
      ],
      exports: [
        %{kind: :agent, key: :leader, from: Ref.ref(:team, :leader)},
        %{kind: :group, key: :workers, from: Ref.ref(:team, :workers)},
        %{kind: :bus, key: :events, from: Ref.ref(:team, :events)}
      ]
    }
  end

  defp deep_plan(count, label) do
    prefix = "component/region/component/team/"
    leader = prefix <> "agent/leader"
    group = prefix <> "group/workers"
    members = if count == 0, do: [], else: for(index <- 1..count, do: "#{group}/#{index}")

    workers =
      members
      |> Enum.with_index(1)
      |> Enum.map(fn {key, index} ->
        member(Integer.to_string(index), %{label: label, value: index}, Integer.to_string(index),
          key: key,
          declaration: group,
          scope: ["region", "team"],
          depends_on: [leader, "bus/events"],
          subscriptions: [%{bus: "bus/events", path: "authoring.work"}]
        )
      end)

    layers =
      if count == 0,
        do: [["bus/events", leader], ["agent/observer"]],
        else: [["bus/events", leader], members, ["agent/observer"]]

    plan(
      [
        agent("leader", %{label: label},
          key: leader,
          declaration: leader,
          scope: ["region", "team"]
        ),
        agent("observer", %{},
          depends_on: [leader | members] ++ ["bus/events"],
          subscriptions: [%{bus: "bus/events", path: "authoring.work"}]
        )
        | workers
      ],
      [bus("events")],
      layers,
      %{
        "observer" => %{key: "agent/observer", kind: :agent},
        "events" => %{key: "bus/events", kind: :bus},
        Ref.ref(:region, :leader) => %{key: leader, kind: :agent},
        Ref.ref(:region, :workers) => %{key: group, kind: :group},
        Ref.ref(:region, :events) => %{key: "bus/events", kind: :bus}
      },
      %{
        ["region"] => %{path: ["region"], agents: count + 1, resources: 0},
        ["region", "team"] => %{path: ["region", "team"], agents: count + 1, resources: 0}
      }
    )
  end

  defp scenario(input, plan), do: scenario(input, plan, input)
  defp scenario(input, plan, normalized), do: %{input: input, normalized: normalized, plan: plan}

  defp plan(agents, resources, layers, lookup, components \\ %{}) do
    %Plan{
      agents: Map.new(agents, &{&1.key, &1}),
      resources: Map.new(resources, &{&1.key, &1}),
      layers: layers,
      lookup: lookup,
      components:
        Map.put(components, [], %{path: [], agents: length(agents), resources: length(resources)})
    }
  end

  defp endpoints(values),
    do: Map.new(values, fn {name, kind} -> {name, %{kind: kind, key: "#{kind}/#{name}"}} end)

  defp agent(local, state \\ %{}, opts \\ []) do
    spec =
      Map.merge(
        %{
          local: local,
          scope: [],
          kind: :agent,
          key: "agent/#{local}",
          declaration: "agent/#{local}",
          module: Fixtures.Worker,
          initial_state: state,
          node: node(),
          depends_on: [],
          parent: nil,
          on_parent_exit: :stop,
          subscriptions: []
        },
        Map.new(opts)
      )

    Map.put(spec, :id, "corpus/" <> spec.key)
  end

  defp member(key, state), do: member(key, state, key)

  defp member(key, state, escaped, opts \\ []) do
    agent(
      "workers",
      state,
      Keyword.merge(
        [key: "group/workers/" <> escaped, declaration: "group/workers", member_key: key],
        opts
      )
    )
  end

  defp bus(local) do
    %{
      local: local,
      scope: [],
      kind: :bus,
      key: "bus/#{local}",
      id: "corpus/bus/#{local}",
      config: [],
      depends_on: [],
      parent: nil,
      on_parent_exit: :stop,
      subscriptions: []
    }
  end
end
