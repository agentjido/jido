defmodule Jido.Agent.TopologyContractTest do
  use Covenant.Case, component: "jido.agent", async: true

  alias Jido.Agent
  alias Jido.Agent.Topology
  alias JidoTest.AgentContract, as: F

  defmodule Child do
    use Jido.Agent, name: "topology_contract_child"

    agent do
      schema Zoi.object(%{
               value: Zoi.string() |> Zoi.default("default"),
               items: Zoi.list(Zoi.string()) |> Zoi.default([])
             })
    end

    routes do
      route "work.one"
      route "work.two"
    end
  end

  defmodule Ports do
    use Jido.Agent.Extension, id: "test.topology.ports"
    def endpoint_kinds, do: [:port]
    def endpoints(_data), do: [%{kind: :port, name: :in}, %{kind: :port, name: :out}]
  end

  defp endpoint(name), do: %{kind: :agent, name: name}

  defp edge(path, to, delivery \\ :single) do
    %{path: path, from: endpoint(:root), to: endpoint(to), delivery: delivery}
  end

  @tag obligation: "jido.agent.I25"
  test "topology values have exact empty, state, member, and connection forms" do
    assert Topology.state(:count) === %{kind: :state, key: :count}
    assert Topology.empty?(%{agents: [], connections: []}) === true

    for value <- [
          %{},
          %{agents: []},
          %{connections: []},
          %{agents: [%{}], connections: []}
        ] do
      assert Topology.empty?(value) === false
    end

    assert {:ok, %{agents: [], connections: []}} = Topology.validate(%{})

    member = %{name: :child, definition: Child, identities: %{1 => "one"}}

    assert {:ok, normalized_member} = Topology.entry(:agent, member)

    assert normalized_member === %{
             name: :child,
             definition: Child,
             count: 1,
             initial_state: %{},
             identities: %{1 => "one"}
           }

    connection = %{path: "work.one", from: endpoint(:root), to: endpoint(:child)}

    assert {:ok, %{delivery: :single} = normalized_connection} =
             Topology.entry(:connect, connection)

    assert Map.drop(normalized_connection, [:delivery]) == connection
    assert {:error, %{code: :invalid_member}} = Topology.entry(:agent, %{name: :child})
  end

  @tag obligation: ["jido.agent.I22", "jido.agent.I25"]
  test "member identities require positive slots and nonempty binary IDs" do
    valid = %{name: :child, definition: Child}

    for identities <- [
          [],
          %URI{},
          %{0 => "zero"},
          %{-1 => "negative"},
          %{1 => ""},
          %{1 => nil},
          %{"1" => "string-slot"}
        ] do
      assert {:error, %Agent.Error{code: :invalid_member_identity, path: [:identities]}} =
               Topology.entry(:agent, Map.put(valid, :identities, identities))
    end

    assert {:ok, _} = Topology.entry(:agent, Map.put(valid, :identities, %{1 => "x"}))
  end

  @tag obligation: ["jido.agent.I22", "jido.agent.I25"]
  test "related validation can be deferred but invalid public member forms still fail" do
    missing = Module.concat(__MODULE__, MissingChild)
    parent = F.definition()

    topology = %{
      agents: [%{name: :offline, definition: missing}],
      connections: []
    }

    assert {:ok, %{agents: [%{definition: ^missing}]}} =
             Topology.normalize(topology, parent, related?: false)

    assert {:error, %Agent.Error{code: :unresolved_definition}} =
             Topology.normalize(topology, parent, [])

    for definition <- [nil, true, false, 1, "agent", []] do
      assert {:error, %Agent.Error{code: :invalid_member}} =
               Topology.normalize(
                 %{agents: [%{name: :bad, definition: definition}], connections: []},
                 parent,
                 []
               )
    end
  end

  @tag obligation: "jido.agent.I28"
  test "connection checks return exact compatible, unchecked, and rejected proofs" do
    base =
      Agent.define!(%{
        name: "topology_checks",
        routes: [%{path: "work.one", handler: %{kind: :pass_through}}],
        topology: %{agents: [%{name: :child, definition: Child}]}
      })

    compatible = %{base | topology: %{base.topology | connections: [edge("work.one", :child)]}}

    assert {:ok,
            [
              %{
                connection: %{path: "work.one"},
                status: :compatible,
                reason: nil
              }
            ]} = Topology.checks(compatible)

    wildcard = %{base | topology: %{base.topology | connections: [edge("work.*", :child)]}}

    assert {:ok,
            [
              %{
                connection: %{path: "work.*"},
                status: :unchecked,
                reason: :wildcard_coverage
              }
            ]} = Topology.checks(wildcard)

    unknown_source =
      Agent.define!(%{
        name: "unknown_source",
        routes: [%{path: "work.one", handler: %{kind: :action, target: F.Return}}],
        topology: %{agents: [%{name: :child, definition: Child}]}
      })

    unchecked = %{
      unknown_source
      | topology: %{unknown_source.topology | connections: [edge("work.one", :child)]}
    }

    assert {:ok, [%{status: :unchecked, reason: :unknown_outputs}]} =
             Topology.checks(unchecked)

    bad_destination =
      %{base | topology: %{base.topology | connections: [edge("missing", :child)]}}

    assert {:error,
            %Agent.Error{
              code: :unaccepted_type,
              details: %{type: "missing", definition: "topology_contract_child"}
            }} = Topology.checks(bad_destination)

    closed_source =
      Agent.define!(%{
        name: "closed_source",
        routes: [
          %{path: "work.one", handler: %{kind: :action, target: F.Return}, emits: []}
        ],
        topology: %{agents: [%{name: :child, definition: Child}]}
      })

    unproduced = %{
      closed_source
      | topology: %{closed_source.topology | connections: [edge("work.one", :child)]}
    }

    assert {:error,
            %Agent.Error{
              code: :unproduced_type,
              details: %{type: "work.one", definition: "closed_source"}
            }} = Topology.checks(unproduced)
  end

  @tag obligation: "jido.agent.I28"
  test "provider endpoints participate in normalization and proof checks" do
    contribution = %{id: Ports.id(), provider: Ports, vsn: Ports.vsn(), data: %{}}

    definition =
      Agent.define!(%{
        name: "provider_endpoints",
        routes: [%{path: "work.one", handler: %{kind: :pass_through}}],
        extensions: [contribution],
        topology: %{
          agents: [%{name: :child, definition: Child}],
          connections: [
            %{
              path: "work.one",
              from: %{kind: :port, name: :out},
              to: endpoint(:child),
              delivery: :single
            },
            %{
              path: "work.one",
              from: endpoint(:root),
              to: %{kind: :port, name: :in},
              delivery: :single
            }
          ]
        }
      })

    assert {:ok, [%{status: :unchecked}, %{status: :compatible}]} =
             Topology.checks(definition)

    assert {:error, %Agent.Error{code: :unknown_endpoint}} =
             Agent.define(%{
               definition
               | topology: %{
                   definition.topology
                   | connections: [
                       %{
                         path: "work.one",
                         from: endpoint(:root),
                         to: %{kind: :port, name: :missing},
                         delivery: :single
                       }
                     ]
                 }
             })
  end

  @tag obligation: "jido.agent.I28"
  test "invalid endpoint and delivery values fail at the final topology boundary" do
    base = %{
      name: "invalid_connections",
      routes: [%{path: "work.one", handler: %{kind: :pass_through}}],
      topology: %{agents: [%{name: :child, definition: Child}]}
    }

    invalid = [
      %{path: "work.one", from: nil, to: endpoint(:child), delivery: :single},
      %{path: "work.one", from: endpoint(:root), to: nil, delivery: :single},
      %{path: "work.one", from: endpoint(:root), to: endpoint(:missing), delivery: :single},
      %{path: "work.one", from: endpoint(:root), to: endpoint(:child), delivery: :fanout}
    ]

    for connection <- invalid do
      assert {:error, %Agent.Error{}} =
               Agent.define(put_in(base, [:topology, :connections], [connection]))
    end
  end

  @tag obligation: "jido.agent.I28"
  test "connection selection validates the type and preserves declaration order" do
    base =
      Agent.define!(%{
        name: "connection_selection",
        routes: [%{path: "work.*", handler: %{kind: :pass_through}}],
        topology: %{
          agents: [
            %{name: :one, definition: Child},
            %{name: :two, definition: Child}
          ]
        }
      })

    definition = %{
      base
      | topology: %{
          base.topology
          | connections: [
              edge("work.*", :one),
              edge("other", :two),
              edge("work.one", :two)
            ]
        }
    }

    assert {:ok, [first, third]} =
             Topology.connections_for(definition, endpoint(:root), "work.one")

    assert first.to.name == :one
    assert third.to.name == :two
    assert {:error, _} = Topology.connections_for(definition, endpoint(:root), "work.*")
  end

  @tag obligation: "jido.agent.I30"
  test "binding resolves nested state references and returns complete child values" do
    definition =
      Agent.define!(%{
        name: "topology_binding",
        schema:
          Zoi.object(%{
            copies: Zoi.integer() |> Zoi.default(2),
            value: Zoi.string() |> Zoi.default("seed")
          }),
        topology: %{
          agents: [
            %{
              name: :child,
              definition: Child,
              count: Topology.state(:copies),
              initial_state: %{
                value: Topology.state(:value),
                items: [Topology.state(:value)]
              }
            }
          ]
        }
      })

    assert {:ok,
            [
              %{
                name: :child,
                definition: child,
                count: 2,
                state: %{value: "seed", items: ["seed"]}
              }
            ]} = Topology.bind(definition, %{copies: 2, value: "seed"})

    assert child === Child.definition()

    assert {:error,
            %Agent.Error{
              code: :missing_state_field,
              path: [:topology, :agents, 0],
              details: %{key: :copies}
            }} = Topology.bind(definition, %{value: "seed"})
  end
end
