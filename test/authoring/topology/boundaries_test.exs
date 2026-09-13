Code.require_file("../support/topology/corpus.exs", __DIR__)

defmodule JidoTest.Authoring.Topology.BoundariesTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Topology
  alias Jido.Topology.{Builder, Codec, Plan, Ref}
  alias JidoTest.Authoring.Compiler
  alias JidoTest.Authoring.Topology.{Cases, Corpus, Fixtures}

  setup do
    Corpus.load_support!()
    :ok
  end

  for {source, message} <- [
        {"duplicate_names", "Duplicate"},
        {"cycle", "cycle"},
        {"missing_endpoint", "Unknown topology endpoint"},
        {"missing_binding", "Import bindings must match"},
        {"bus_identity", "Topology owns Bus"}
      ] do
    @source source
    @message message
    test "invalid declaration: #{@source}" do
      if @source == "missing_binding", do: Corpus.load!(:nested)
      path = Corpus.fixture("invalid/#{@source}.exs")
      error = assert_raise CompileError, fn -> Compiler.compile_file(path) end
      assert error.file == path
      assert error.line > 0
      assert error.description =~ @message
    end
  end

  for {source, field} <- [{"startup", :concurrency}, {"ownership_policy", :on_parent_exit}] do
    @tag source: source, field: field
    test "invalid DSL option: #{source}", %{source: source, field: field} do
      error =
        assert_raise Spark.Error.DslError, fn ->
          Compiler.compile_file(Corpus.fixture("invalid/#{source}.exs"))
        end

      assert Exception.message(error) =~ Atom.to_string(field)
      assert error.path != []
    end
  end

  test "invalid graphs and bindings fail in direct and Builder forms" do
    worker = %{key: :worker, module: Fixtures.Worker}

    cases = [
      %{agents: [worker, worker]},
      %{
        agents: [
          %{worker | key: :a} |> Map.put(:depends_on, [:b]),
          %{worker | key: :b} |> Map.put(:depends_on, [:a])
        ]
      },
      %{agents: [Map.put(worker, :depends_on, [:missing])]},
      %{
        includes: [
          %{
            key: :team,
            topology: Cases.child_attrs(),
            inputs: %{label: "child"},
            bindings: %{}
          }
        ]
      },
      %{
        agents: [worker],
        includes: [
          %{
            key: :team,
            topology: Cases.child_attrs(),
            inputs: %{label: "child"},
            bindings: %{events: :worker}
          }
        ]
      },
      %{resources: [%{key: :events}], exports: [%{kind: :agent, key: :worker, from: :events}]}
    ]

    for attrs <- cases do
      attrs = Map.put(attrs, :name, "invalid_graph")

      for result <- [
            Topology.new(attrs),
            Topology.new(Map.to_list(attrs)),
            Builder.build(Builder.new(attrs))
          ] do
        assert {:error, %Jido.Error.ValidationError{}} = result
      end
    end
  end

  test "an empty definition produces an empty plan" do
    definition = Topology.new!(name: "empty")
    assert {:ok, document, registry} = Codec.encode(definition)
    assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    assert {:ok, instance} = Topology.instantiate(definition, id: "empty")

    assert instance.plan === %Plan{
             agents: %{},
             resources: %{},
             layers: [],
             lookup: %{},
             components: %{[] => %{path: [], agents: 0, resources: 0}}
           }
  end

  test "a combined host keeps the control Agent separate from the Topology" do
    Corpus.load!(:combined)
    module = Corpus.spec(:combined).module
    topology = module.topology()
    owner = module.owner()
    assert owner === module.definition()
    assert owner.metadata === %{"kind" => "owner"}
    assert topology.metadata === %{"kind" => "topology", :role_count => 1}
    assert {:ok, agent} = module.new_agent(id: "owner", state: %{value: 7})
    assert %Agent{id: "owner", state: %{value: 7}, module: ^module} = agent
    assert {:ok, instance} = module.new(id: "topology")
    assert %Topology.Instance{id: "topology", definition: ^topology} = instance
    assert Map.keys(instance.plan.agents) == ["agent/worker"]

    signal = module.set_signal!(9)
    assert signal.type == "owner.set"
    assert signal.source == "/authoring/owner"
    assert {:ok, %{state: %{value: 9}}, []} = Agent.cmd(agent, signal)
    assert module.topology() === topology
    assert {:ok, document, registry} = Agent.Codec.encode(owner)
    assert {:ok, ^owner} = Agent.Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
  end

  test "Plugin contributions appear in plans but never change saved declarations" do
    Corpus.load!(:plugin)
    spec = Corpus.spec(:plugin)
    definition = spec.module.topology()
    assert definition.resources == []
    assert definition.connections == []

    for form <- Corpus.forms() do
      current = Corpus.definition(spec, form)
      assert {:ok, instance} = Topology.instantiate(current, id: "corpus")

      assert Map.keys(instance.plan.resources) |> Enum.sort() == [
               "bus/inbox_solo",
               "bus/inbox_workers"
             ]

      assert instance.definition === definition
      assert {:ok, document} = Codec.encode(instance.definition, spec.registry)
      assert document === spec.document
    end
  end

  test "stored child definitions retain exports and reject private or invalid references" do
    Corpus.load!(:nested)
    spec = Corpus.spec(:nested)
    assert {:ok, instance} = Codec.decode(spec.document, spec.registry, id: "corpus")

    assert Plan.resolve(instance.plan, Ref.ref(:team, :public_worker), :agent) ==
             "component/team/agent/worker"

    assert Plan.resolve(instance.plan, Ref.ref(:team, :worker), :agent) == nil

    [child] = spec.document["includes"]

    for nested <- [
          Map.put(child["topology"], "schema", "untrusted/schema"),
          Map.put(child["topology"], "exports", [
            %{"key" => "public_worker", "kind" => "bus", "from" => "worker"}
          ])
        ] do
      invalid = Map.put(spec.document, "includes", [Map.put(child, "topology", nested)])
      assert {:error, %Jido.Error.ValidationError{}} = Codec.decode(invalid, spec.registry)
    end
  end

  test "Builder reuse preserves the original and the first failure" do
    Corpus.load!(:minimal)
    base = Corpus.builder(Corpus.spec(:minimal))
    original = Builder.build!(base)
    branch = Builder.agent(base, :second, Fixtures.Worker)
    assert Enum.map(Builder.build!(branch).agents, & &1.key) == ["worker", "second"]
    assert Builder.build!(base) === original
    failed = Builder.name(base, "")
    assert {:error, error} = Builder.build(failed)
    assert {:error, ^error} = failed |> Builder.name("valid") |> Builder.build()
  end

  for field <- [:concurrency, :max_agents, :retry_interval, :task_timeout] do
    @tag field: field
    test "#{field} rejects zero, negative, and non-integer values across data and JSON", %{
      field: field
    } do
      Corpus.load!(:configured)
      spec = Corpus.spec(:configured)

      for value <- [0, -1, 1.5, "1", false] do
        attrs = put_in(spec.attrs, [:startup, field], value)
        document = put_in(spec.document, ["startup", Atom.to_string(field)], value)

        for result <- [
              Topology.new(attrs),
              Topology.new(Map.to_list(attrs)),
              Builder.build(Builder.new(attrs)),
              Codec.decode(document, spec.registry)
            ] do
          assert {:error,
                  %Jido.Error.ValidationError{
                    message: "Expected a positive integer",
                    details: %{field: ^field}
                  }} = result
        end
      end

      assert {:ok, valid} = Codec.decode(spec.document, spec.registry, id: "corpus")
      assert valid.plan === hd(spec.scenarios).plan
    end
  end

  test "reserved Bus identity options and unknown ownership policies cannot enter definitions" do
    Corpus.load!(:configured)
    spec = Corpus.spec(:configured)

    for reserved <- [:name, :registry, :jido] do
      attrs = put_in(spec.attrs, [:resources, Access.at(0), :config], [{reserved, "foreign"}])

      assert {:error,
              %Jido.Error.ValidationError{
                message: "Topology owns Bus name, Registry, and Jido scope"
              }} = Topology.new(attrs)

      assert {:error, %Jido.Error.ValidationError{}} = Builder.build(Builder.new(attrs))
    end

    attrs = put_in(spec.attrs, [:relationships, Access.at(0), :on_parent_exit], :restart)

    assert {:error,
            %Jido.Error.ValidationError{details: %{field: :on_parent_exit, value: :restart}}} =
             Topology.new(attrs)

    document = put_in(spec.document, ["relationships", Access.at(0), "on_parent_exit"], "restart")

    assert {:error, %Jido.Error.ValidationError{message: "Unknown topology policy"}} =
             Codec.decode(document, spec.registry)
  end

  test "remote placement is serializable but a remote-to-local Bus subscription is rejected" do
    Corpus.load!(:configured)
    spec = Corpus.spec(:configured)

    for form <- Corpus.forms() do
      original = Corpus.definition(spec, form)

      builder =
        Builder.new(original) |> Builder.subscribe(:remote, to: :events, path: "authoring.work")

      assert {:ok, definition} = Builder.build(builder)
      assert {:ok, document} = Codec.encode(definition, spec.registry)
      assert {:ok, ^definition} = Codec.decode(document, spec.registry)

      for result <- [
            Topology.instantiate(definition, id: "corpus"),
            Builder.build(builder, id: "corpus"),
            Codec.decode(document, spec.registry, id: "corpus")
          ] do
        assert {:error,
                %Jido.Error.ValidationError{
                  message: "A remote topology Agent cannot subscribe to a local Bus"
                }} = result
      end

      assert {:ok, valid} = Topology.instantiate(original, id: "corpus")
      assert valid.plan === hd(spec.scenarios).plan
    end
  end
end
