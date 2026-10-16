defmodule JidoTest.Contract.AgentAuthoringTest do
  use Covenant.Case, component: "jido.agent", async: false

  alias Jido.Agent
  alias Jido.Error.ValidationError
  alias JidoTest.AgentContract, as: F

  setup do
    previous = Code.compiler_options(debug_info: true)
    Process.register(self(), F.Observer)
    on_exit(fn -> Code.compiler_options(previous) end)
    :ok
  end

  @tag obligation: ["jido.agent.I21", "jido.agent.I24", "jido.agent.I25"]
  test "generated public functions construct definitions, instances, and Signals" do
    F.with_agent(
      """
      agent do
        schema F.schema()
        plugin F.First
      end
      routes do
        signal_source "/default"
        route "test.add", F.Add, as: :add, defaults: %{amount: 2}
      end
      """,
      fn module ->
        for {name, arity} <- [
              definition: 0,
              vsn: 0,
              domain_schema: 0,
              complete_schema: 0,
              new: 0,
              new: 1,
              new!: 0,
              new!: 1,
              cmd: 2,
              cmd: 3,
              route_action!: 1,
              add_signal: 1,
              add_signal: 2
            ],
            do: assert(function_exported?(module, name, arity))

        assert module.vsn() == 1
        assert module.definition().vsn == 1
        assert module.definition().module == module
        assert module.domain_schema() === F.schema()
        assert {:ok, complete} = Agent.complete_schema(module.definition())
        assert module.complete_schema() === complete
        assert {:ok, instance} = module.new(id: "fixed")
        assert module.new!(id: "fixed") === instance
        assert {:ok, %{state: %{first: 0, count: 0}}} = module.new()
        assert module.new!().id != instance.id
        assert {:ok, default} = module.add_signal(%{})
        assert default.data === %{}
        assert default.source == "/default"
        assert default.type == "test.add"
        assert {:ok, %{state: %{count: 2, first: 1}}, []} = module.cmd(instance, default)

        assert {:ok, signal} =
                 module.add_signal(%{amount: 4},
                   source: "/caller",
                   subject: "subject",
                   id: "signal-id"
                 )

        assert {signal.type, signal.data, signal.source, signal.subject, signal.id} ===
                 {"test.add", %{amount: 4}, "/caller", "subject", "signal-id"}

        assert {:ok, %{state: %{count: 4}}, []} =
                 module.cmd(instance, signal, context: %{request: 1})

        envelope = [
          time: "2026-10-15T12:00:00Z",
          datacontenttype: "application/json",
          dataschema: "https://example.test/schema",
          extensions: %{"trace" => "contract"}
        ]

        assert {:ok, enriched} = module.add_signal(%{}, envelope)
        assert Map.take(enriched, Keyword.keys(envelope)) === Map.new(envelope)
        assert {:ok, invalid_input} = module.add_signal(%{amount: "invalid"})
        assert {:error, _} = module.cmd(instance, invalid_input)

        for input <- [nil, [], [amount: 2], %URI{}],
            do: assert({:error, %ValidationError{}} = module.add_signal(input))

        for opts <- [
              [type: "other"],
              [data: %{amount: 9}],
              [unknown: 1],
              :invalid,
              [:invalid],
              [source: "bad source"]
            ] do
          assert {:error, _} = module.add_signal(%{}, opts)
        end

        assert {:error, error} = module.new(id: "")
        assert_raise error.__struct__, fn -> module.new!(id: "") end
      end
    )
  end

  @tag obligation: ["jido.agent.I4", "jido.agent.I3", "jido.agent.I21"]
  test "invalid DSL declarations fail at compile time with source locations" do
    for {body, options} <- [
          {"agent do\nend", ", name: \"duplicate\""},
          {"agent do\nend", ", unknown: 1"},
          {"agent do\nend", ", schema: F.schema()"},
          {"agent do\nend", ", metadata: %{owner: :contract}"},
          {"agent do\nend", ", routes: [{\"test.run\", F.Return}]"},
          {"agent do\nend", ", plugins: [F.First]"},
          {"agent do\nend", ", vsn: 0"},
          {"agent do\nend", ", vsn: nil"},
          {"routes do\nroute \"test.run\", F.Return\nend", ""},
          {"agent do\nmetadata []\nend", ""},
          {"agent do\nschema Zoi.integer()\nend", ""},
          {"agent do\nplugin F.First, config: :invalid\nend", ""},
          {"agent do\nplugin Enum\nend", ""},
          {"agent do\nend\nroutes do\nroute \"test.run\", Enum\nend", ""},
          {"agent do\nend\nroutes do\nroute \"test.run\", F.Return, priority: 1, priority: 2\nend",
           ""},
          {"agent do\nend\nroutes do\nroute \"test.run\", F.Return, as: :run\nend", ""},
          {"agent do\nend\nroutes do\nsignal_source \"bad source\"\nroute \"test.run\", F.Return, as: :run\nend",
           ""},
          {"agent do\nend\nroutes do\nsignal_source \"/test\"\nroute \"test.*\", F.Return, as: :run\nend",
           ""},
          {"agent do\nend\nroutes do\nsignal_source \"/test\"\nroute \"test.run\", F.Return, as: :run, match: &is_map/1\nend",
           ""},
          {"agent do\nend\nroutes do\nsignal_source \"/test\"\nroute \"test.run\", F.Return, as: :run\nroute \"test.run\", F.Add\nend",
           ""},
          {"agent do\nend\nroutes do\nsignal_source \"/test\"\nroute \"test.one\", F.Return, as: :run\nroute \"test.two\", F.Add, as: :run\nend",
           ""},
          {"agent do\nend\ndef run_signal(_), do: :conflict\nroutes do\nsignal_source \"/test\"\nroute \"test.run\", F.Return, as: :run\nend",
           ""},
          {"agent do\nend\nroutes do\nroute \"test.run\" do\nend\nend", ""},
          {"agent do\nend\nroutes do\nroute \"test.run\", F.Return, ref: F.Add\nend", ""},
          {"agent do\nend\nroutes do\nroute \"test.run\", ref: F.Add\nend", ""}
        ] do
      error =
        try do
          F.with_agent(body, fn _ -> :ok end, options)
          flunk("invalid DSL compiled: #{body}")
        rescue
          error in [CompileError, Spark.Error.DslError] -> error
        end

      assert Exception.message(error) =~ "authoring_fixture.ex"

      if is_struct(error, CompileError) do
        assert error.line > 0
        assert is_binary(error.description) and byte_size(error.description) > 0
      end
    end
  end

  @tag obligation: ["jido.agent.I6", "jido.agent.I24"]
  test "reloaded Plugin state schemas are current and conflicts raise at accessors" do
    F.with_agent(
      """
      agent do
        schema F.schema()
        plugin __MODULE__.Owned
      end
      defmodule Owned do
        use Jido.Plugin
        def state_spec(_), do: {:owned, Zoi.integer() |> Zoi.default(1)}
      end
      """,
      fn module ->
        plugin = Module.concat(module, Owned)
        definition = module.definition()
        assert module.new!().state.owned == 1

        reload("""
        defmodule #{inspect(plugin)} do
          use Jido.Plugin
          def state_spec(_), do: {:owned, Zoi.integer() |> Zoi.default(2)}
        end
        """)

        assert module.definition() === definition
        assert module.new!().state.owned == 2
        assert {:ok, %{owned: 2}} = Zoi.parse(module.complete_schema(), %{})
        assert Agent.instantiate!(definition).state.owned == 2

        reload("""
        defmodule #{inspect(plugin)} do
          use Jido.Plugin
          def state_spec(_), do: {:count, Zoi.integer() |> Zoi.default(2)}
        end
        """)

        assert {:error, error} = module.new()

        for bang <- [&module.new!/0, &module.definition/0, &module.complete_schema/0] do
          raised = assert_raise error.__struct__, bang

          assert Map.drop(Map.from_struct(raised), [:stacktrace]) ===
                   Map.drop(Map.from_struct(error), [:stacktrace])
        end

        assert {:error, _} = Agent.instantiate(definition)
      end
    )
  end

  @tag obligation: "jido.agent.I6"
  test "an unchanged module rejects a reloaded invalid Action contract" do
    F.with_agent(
      """
      agent do
      end
      routes do
        route "test.run", __MODULE__.Run
      end
      defmodule Run do
        use Jido.Action, name: "contract_reload"
        def run(_, _), do: {:ok, %{}}
      end
      """,
      fn module ->
        assert module.definition().routes != []
        action = Module.concat(module, Run)
        reload("defmodule #{inspect(action)} do\ndef run(_, _), do: {:ok, %{}}\nend")
        assert {:error, error} = module.new()
        assert_raise error.__struct__, fn -> module.definition() end
        assert_raise error.__struct__, fn -> module.complete_schema() end
      end
    )
  end

  @tag obligation: ["jido.agent.I22", "jido.agent.I1"]
  test "computed options and extensions evaluate once and lower to ordinary values" do
    F.with_agent(
      """
      agent do
        schema F.schema()
        label :owner, "contract-owner"
      end
      routes do
        signal_source "/extension"
        route "test.run", ref: F.Return, as: :run, defaults: %{amount: 1}
        route "test.add", ref: F.Add
      end
      """,
      fn module ->
        assert_receive {:observed, "computed description"}
        assert_receive {:observed, [F.Labels]}
        assert_receive {:observed, {:lowered, F.Labels}}
        refute_received {:observed, _}

        expected =
          F.definition(
            module: module,
            vsn: 1,
            description: "computed description",
            metadata: %{owner: "contract-owner"},
            routes: [{"test.run", {F.Return, %{amount: 1}}}, {"test.add", F.Add}]
          )

        assert module.definition() === expected
        assert {:ok, signal} = module.run_signal(%{})
        assert {:ok, _, []} = module.cmd(module.new!(), signal)

        assert {:ok, lowered} =
                 Agent.Extension.lower(
                   [F.Labels, F.OrderedExtension],
                   %{metadata: %{}, routes: []},
                   [%F.Label{key: :owner, value: "first"}]
                 )

        assert lowered == %{metadata: %{owner: "first", seen: "first"}, routes: []}
      end,
      ", description: F.observe(\"computed description\"), extensions: F.observe([F.Labels])"
    )
  end

  @tag obligation: "jido.agent.I22"
  test "invalid lowered fields and unconsumed entities fail at the core boundary" do
    for {extension, body} <- [
          {F.BadExtension, ""},
          {F.Unclaimed, "label :key, 1"},
          {F.NoLowerExtension, ""}
        ] do
      assert_raise CompileError, fn ->
        F.with_agent(
          "agent do\n#{body}\nend",
          fn _ -> :ok end,
          ", extensions: [#{inspect(extension)}]"
        )
      end
    end

    for extensions <- [[F.InvalidExtension], [F.RejectedExtension], [Enum], [nil], :invalid] do
      assert {:error, %ValidationError{}} =
               Agent.Extension.lower(extensions, %{metadata: %{}, routes: []}, [])
    end
  end

  @tag obligation: ["jido.agent.I21", "jido.agent.I22", "jido.agent.I25"]
  test "inline route declarations keep their helper and execution behavior" do
    for declaration <- [
          "action %{amount: amount}, schema: Zoi.object(%{amount: Zoi.integer()}), context: context do\n{:ok, %{context.agent_state | count: amount}}\nend",
          "action schema: Zoi.object(%{amount: Zoi.integer()}), context: context do\n%{amount: amount} -> {:ok, %{context.agent_state | count: amount}}\nend"
        ] do
      F.with_agent(
        """
        agent do
          schema F.schema()
        end
        routes do
          signal_source "/inline"
          route "inline.add", as: :add, defaults: %{amount: 6} do
            #{declaration}
          end
        end
        """,
        fn module ->
          action = module.route_action!("inline.add")
          assert is_atom(action) and function_exported?(action, :run, 2)
          assert module.definition().routes |> Enum.map(& &1.target) == [{action, %{amount: 6}}]
          assert {:ok, signal} = module.add_signal(%{})
          assert {:ok, %{state: %{count: 6}}, []} = module.cmd(module.new!(), signal)
        end
      )
    end
  end

  @tag obligation: "jido.agent.I3"
  test "dependency errors identify the authored route or Plugin line" do
    for {body, line} <- [
          {"agent do\nend\nroutes do\nroute \"test.run\", Enum\nend", 7},
          {"agent do\nend\nroutes do\nroute \"test.first\", F.Return\nroute \"test.second\", Enum\nend",
           8},
          {"agent do\nschema F.schema()\nplugin F.First, config: [key: :count]\nend", 4},
          {"agent do\nplugin Enum\nend", 5}
        ] do
      error = assert_raise CompileError, fn -> F.with_agent(body, fn _ -> :ok end) end
      assert Path.basename(error.file) == "authoring_fixture.ex"
      assert error.line == line
    end
  end

  @tag obligation: "jido.agent.I22"
  test "extension validation rejects duplicate owners, invalid configuration, and invalid results" do
    config = %{metadata: %{}, routes: []}

    for {extensions, attrs, entities} <- [
          {[F.Labels, F.Labels], config, []},
          {[], nil, []},
          {[], %URI{}, []},
          {[], config, [1 | :tail]},
          {[F.Labels | :tail], config, []},
          {[F.Unclaimed], config, [%F.Label{key: :owner, value: 1}]},
          {[F.InvalidExtension], config, []},
          {[F.StructExtension], config, []},
          {[F.ImproperExtension], config, []},
          {[F.AtomErrorExtension], config, []}
        ] do
      assert {:error, %ValidationError{}} = Agent.Extension.lower(extensions, attrs, entities)
    end

    target = %Jido.Agent.Extension.RouteTarget{option: :ref, value: F.Add}

    assert {:ok, %{routes: [%{target: F.Add}, %{target: {F.Add, %{amount: 2}}}]}} =
             Agent.Extension.lower(
               [F.Labels],
               %{metadata: %{}, routes: [%{target: target}, %{target: {target, %{amount: 2}}}]},
               []
             )

    for extensions <- [[], [F.Labels, F.OtherOwner], [F.InvalidClaims]],
        route_target <- [target, {target, %{amount: 2}}] do
      assert {:error, %ValidationError{}} =
               Agent.Extension.lower(extensions, %{routes: [%{target: route_target}]}, [])
    end

    for claims <- [[:ref, "invalid"], [:ref | :tail]] do
      Process.put(:agent_contract_claims, claims)

      assert {:error, %ValidationError{} = error} =
               Agent.Extension.lower([F.InvalidClaims], %{routes: [%{target: target}]}, [])

      assert error.message ==
               "Agent extension route_target_options/0 must return unique atom names"
    end

    assert {:error, %ValidationError{} = error} =
             Agent.Extension.lower(
               [F.Labels],
               %{routes: [%{target: target}, %{target: %{target | option: "invalid"}}]},
               []
             )

    assert error.message == "Invalid Agent extension route target option"

    assert {:error, %ValidationError{}} =
             Agent.Extension.lower(
               [F.Labels],
               %{routes: [%{target: %{target | option: nil}}]},
               []
             )
  end

  @tag obligation: ["jido.agent.I21", "jido.agent.I22"]
  test "extensions cannot leave exposed Signal helpers with missing, duplicate, or conditional routes" do
    for mode <- [:remove, :duplicate, :predicate] do
      assert_raise CompileError, fn ->
        F.with_agent(
          """
          agent do
            metadata %{rewrite: #{inspect(mode)}}
          end
          routes do
            signal_source "/contract"
            route "test.run", F.Return, as: :run
          end
          """,
          fn _ -> :ok end,
          ", extensions: [F.RewriteRoutes]"
        )
      end
    end
  end

  @tag obligation: "jido.agent.I21"
  test "both generated helper arities reject name conflicts" do
    for args <- ["_input", "_input, _opts"] do
      assert_raise CompileError, fn ->
        F.with_agent(
          """
          agent do
          end
          def run_signal(#{args}), do: :conflict
          routes do
            signal_source "/contract"
            route "test.run", F.Return, as: :run
          end
          """,
          fn _ -> :ok end
        )
      end
    end
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I12", "jido.agent.I13"]
  test "unexposed DSL routes keep predicates and block options" do
    F.with_agent(
      """
      agent do
        schema F.schema()
      end
      routes do
        route "raw.*", F.Return, [] do
          match &F.match?/1
          priority 4
          defaults %{amount: 2}
        end
      end
      """,
      fn module ->
        expected =
          F.definition(
            module: module,
            vsn: 1,
            routes: [{"raw.*", {F.Return, %{amount: 2}}, match: &F.match?/1, priority: 4}]
          )

        assert module.definition() === expected
        refute function_exported?(module, :raw_signal, 1)
        assert {:ok, _, []} = module.cmd(module.new!(), F.signal(%{}, "raw.run"))

        assert {:error, %Jido.Error.RoutingError{}} =
                 module.cmd(module.new!(), F.signal(nil, "raw.run"))
      end
    )
  end

  defp reload(source) do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      Code.compile_string(source, "contract_reload.ex")
    end)
  end

  @tag obligation: "jido.agent.I22"
  test "extension declarations reject non-module values" do
    for extension <- [1, "not a module", %URI{}, JidoTest.MissingAuthoringExtension] do
      assert {:error, %ValidationError{}} =
               Agent.Extension.lower([extension], %{metadata: %{}, routes: []}, [])
    end
  end

  @tag obligation: "jido.agent.I3"
  test "invalid schema, metadata, and Plugin options report their authored line" do
    for {body, line} <- [
          {"agent do\n  schema Zoi.integer()\nend", 5},
          {"agent do\n  schema Zoi.integer()\n  metadata %{owner: :contract}\nend", 5},
          {"agent do\n  plugin F.First, config: :invalid\nend", 5},
          {"agent do\n  plugin F.First\n  plugin F.Second, config: :invalid\nend", 6}
        ] do
      error = assert_raise CompileError, fn -> F.with_agent(body, fn _ -> :ok end) end
      assert error.line == line
    end

    error =
      assert_raise Spark.Error.DslError, fn ->
        F.with_agent("agent do\n  metadata []\nend", fn _ -> :ok end)
      end

    assert Exception.message(error) =~ "authoring_fixture.ex:4"
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I22"]
  test "anonymous schema values report their authored block line" do
    for field <- [
          "Zoi.any() |> Zoi.default(fn -> :ok end)",
          "Zoi.integer() |> Zoi.refine(fn value -> {:ok, value} end)"
        ] do
      error =
        assert_raise Spark.Error.DslError, fn ->
          F.with_agent("agent do\n  schema Zoi.object(%{value: #{field}})\nend", fn _ -> :ok end)
        end

      assert Exception.message(error) =~ "authoring_fixture.ex:4"
    end
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I22"]
  test "static MFA schema rules retain their validation behavior" do
    F.with_agent(
      """
      agent do
        schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(1) |> Zoi.refine({__MODULE__, :positive, []})})
      end
      def positive(value, _opts), do: if(value > 0, do: :ok, else: {:error, "must be positive"})
      """,
      fn module ->
        assert module.new!().state === %{value: 1}
        assert {:error, %ValidationError{}} = module.new(state: %{value: 0})
      end
    )
  end

  @tag obligation: "jido.agent.I22"
  test "whole option maps, lists, and module attributes use one evaluation" do
    for expression <- [
          "%{name: \"contract\", description: F.observe(\"once\")}",
          "[name: \"contract\", description: F.observe(\"once\")]",
          "@agent_options"
        ] do
      module = Module.concat(F, "Options#{System.unique_integer([:positive])}")

      prefix =
        if expression == "@agent_options",
          do: "@agent_options F.observe([name: \"contract\", description: \"once\"])",
          else: ""

      source = """
      defmodule #{inspect(module)} do
        alias JidoTest.AgentContract, as: F
        #{prefix}
        use Jido.Agent, #{expression}
        agent do
        end
      end
      """

      JidoTest.AuthoringCompiler.with_compiled(
        source,
        fn _ ->
          assert module.definition().description == "once"
          assert module.new!().state == %{}
          assert_receive {:observed, _}
          refute_received {:observed, _}
        end,
        modules: [module],
        timeout: 2_000
      )
    end
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I22"]
  test "inline routes reject combined targets, multiple Actions, and malformed Action arguments" do
    callback = "action do\n _ -> {:ok, %{}}\nend"

    for route <- [
          "route \"inline.run\", F.Return do\n#{callback}\nend",
          "route \"inline.run\" do\n#{callback}\n#{callback}\nend",
          "route \"inline.run\" do\naction :invalid\nend",
          "route \"inline.run\" do\naction [:invalid]\nend",
          "route \"inline.run\" do\naction %{}, :invalid\nend",
          "route \"inline.run\" do\naction %{}, :invalid, :invalid\nend"
        ] do
      assert_raise CompileError, fn ->
        F.with_agent("agent do\nend\nroutes do\n#{route}\nend", fn _ -> :ok end)
      end
    end
  end

  @tag obligation: ["jido.agent.I13", "jido.agent.I22"]
  test "a lone inline Action and remaining route block fields retain their behavior" do
    for declaration <- [
          "action do\n _ -> {:ok, %{count: 6, enabled: true, note: \"default\", settings: %{a: 1, b: 2}}}\nend",
          "priority 7\naction %{amount: n}, context: context do\n{:ok, %{context.agent_state | count: n}}\nend\ndefaults %{amount: 6}\nmatch &F.match?/1",
          "defaults %{amount: 6}\naction %{amount: amount} do\n{:ok, %{count: amount, enabled: true, note: \"default\", settings: %{a: 1, b: 2}}}\nend"
        ] do
      F.with_agent(
        "agent do\nschema F.schema()\nend\nroutes do\nroute \"inline.run\" do\n#{declaration}\nend\nend",
        fn module ->
          assert {:ok, %{state: %{count: 6}}, []} =
                   module.cmd(module.new!(), F.signal(%{}, "inline.run"))

          [route] = module.definition().routes

          if declaration =~ "priority" do
            assert route.priority == 7
            assert route.match === (&F.match?/1)
          end
        end
      )
    end
  end

  @tag obligation: "jido.agent.I22"
  test "a lowering callback returns its supplied validation error" do
    expected = Jido.Error.validation_error("extension rejected")

    assert {:error, actual} =
             Agent.Extension.lower([F.RejectedExtension], %{metadata: %{}, routes: []}, [])

    assert Map.delete(actual, :stacktrace) === Map.delete(expected, :stacktrace)
  end

  @tag obligation: "jido.agent.I22"
  test "route target claims retain plain routes and reject non-atom target options" do
    target = %Jido.Agent.Extension.RouteTarget{option: :ref, value: F.Add}
    config = %{metadata: %{}, routes: [%{target: target}]}
    assert {:ok, %{routes: [%{target: F.Add}]}} = Agent.Extension.lower([F.Labels], config, [])

    mixed = %{config | routes: [%{target: F.Return}, %{target: target}]}

    assert {:ok, %{routes: [%{target: F.Return}, %{target: F.Add}]}} =
             Agent.Extension.lower([F.Labels], mixed, [])

    for extensions <- [[F.Labels], [1]] do
      invalid = %{config | routes: [%{target: %{target | option: "ref"}}]}
      assert {:error, %ValidationError{}} = Agent.Extension.lower(extensions, invalid, [])
    end

    assert {:error, %ValidationError{}} = Agent.Extension.lower([1], config, [])
  end

  @tag obligation: "jido.agent.I22"
  test "route target option callbacks must return unique atom names" do
    target = %Jido.Agent.Extension.RouteTarget{option: :ref, value: F.Add}

    for options <- [nil, 1, "ref", [:ref, 1], [:ref, :other, :other]] do
      Process.put(:contract_route_options, options)

      assert {:error, %ValidationError{}} =
               Agent.Extension.lower(
                 [F.OptionNames],
                 %{metadata: %{}, routes: [%{target: target}]},
                 []
               )
    end
  end

  @tag obligation: ["jido.agent.I21", "jido.agent.I22", "jido.agent.I23"]
  test "authoring and generated helper errors have nonempty messages" do
    config = %{metadata: %{}, routes: []}

    for result <- [
          Agent.Extension.lower(:invalid, config, []),
          Agent.Extension.lower([], %URI{}, []),
          Agent.Extension.lower([F.Labels, F.Labels], config, []),
          Agent.Extension.lower([F.InvalidExtension], config, []),
          Agent.Extension.lower(
            [F.InvalidClaims],
            %{routes: [%{target: %Jido.Agent.Extension.RouteTarget{option: :ref, value: F.Add}}]},
            []
          ),
          Agent.Extension.lower(
            [F.Labels, F.OtherOwner],
            %{routes: [%{target: %Jido.Agent.Extension.RouteTarget{option: :ref, value: F.Add}}]},
            []
          ),
          Agent.Extension.lower(
            [F.Labels],
            %{
              routes: [%{target: %Jido.Agent.Extension.RouteTarget{option: "ref", value: F.Add}}]
            },
            []
          ),
          Agent.Extension.lower([Enum], config, []),
          Agent.Extension.lower([F.Unclaimed], config, [%F.Label{key: :k, value: 1}])
        ] do
      assert {:error, %ValidationError{message: message}} = result
      assert is_binary(message) and byte_size(message) > 0
    end

    F.with_agent(
      "agent do\nend\nroutes do\nsignal_source \"/contract\"\nroute \"test.run\", F.Return, as: :run\nend",
      fn module ->
        assert {:error, %ValidationError{message: message}} = module.run_signal(nil)
        assert is_binary(message) and byte_size(message) > 0
      end
    )
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I22", "jido.agent.I24"]
  test "a bare Agent module keeps the empty canonical definition" do
    F.with_agent("", fn module ->
      definition = module.definition()
      assert definition.module == module
      assert definition.routes == []
      assert definition.plugins == []
      assert definition.metadata == %{}
      assert module.new!().state == %{}
    end)

    assert_raise CompileError, fn -> F.with_agent("", fn _ -> :ok end, ", vsn: 0") end
  end

  @tag obligation: ["jido.agent.I21", "jido.agent.I22"]
  test "one exposed route remains valid after extension lowering" do
    F.with_agent(
      "agent do\nschema F.schema()\nlabel :owner, \"one\"\nend\nroutes do\nsignal_source \"/one\"\nroute \"test.run\", ref: F.Return, as: :run\nend",
      fn module ->
        assert %{metadata: %{owner: "one"}, routes: [%{path: "test.run", target: F.Return}]} =
                 module.definition()

        assert {:ok, signal} = module.run_signal(%{})
        assert {:ok, _, []} = module.cmd(module.new!(), signal)
      end,
      ", extensions: [F.Labels]"
    )
  end

  @tag obligation: ["jido.agent.I12", "jido.agent.I13", "jido.agent.I22"]
  test "an unexposed route accepts its predicate as a keyword option" do
    F.with_agent(
      "agent do\nschema F.schema()\nend\nroutes do\nroute \"test.*\", F.Return, match: &F.match?/1, defaults: %{amount: 2}\nend",
      fn module ->
        assert [%{match: predicate, target: {F.Return, %{amount: 2}}}] =
                 module.definition().routes

        assert predicate === (&F.match?/1)
        assert {:ok, _, []} = module.cmd(module.new!(), F.signal(%{}))
        assert {:error, %Jido.Error.RoutingError{}} = module.cmd(module.new!(), F.signal(nil))
      end
    )
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I22", "jido.agent.I25"]
  test "route arities preserve module and extension targets with empty options" do
    for declaration <- [
          ~s(route "test.run", F.Return),
          ~s(route "test.run", F.Return, []),
          ~s(route "test.run", F.Return, [] do\nend),
          ~s(route "test.run", [ref: F.Return], [])
        ] do
      F.with_agent(
        "agent do\nend\nroutes do\n#{declaration}\nend",
        fn module ->
          assert module.definition().routes ===
                   F.definition(routes: [{"test.run", F.Return}]).routes

          assert {:ok, _, []} = module.cmd(module.new!(), F.signal())
        end,
        ", extensions: [F.Labels]"
      )
    end
  end
end
