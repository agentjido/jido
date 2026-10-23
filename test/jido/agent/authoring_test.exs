defmodule JidoTest.Agent.AuthoringTest do
  use Covenant.Case, component: "jido.agent", async: false

  alias Jido.Agent

  setup do
    # Spark records source locations only when debug information is enabled.
    previous = Code.compiler_options(debug_info: true)
    on_exit(fn -> Code.compiler_options(previous) end)
    :ok
  end

  def observe_count(value, _opts) do
    send(self(), {:parsed_live_count, value})
    :ok
  end

  defmodule Add do
    use Jido.Action,
      name: "authoring_add",
      schema: Zoi.object(%{amount: Zoi.integer(), flag: Zoi.boolean() |> Zoi.default(false)}),
      output_schema: Zoi.any()

    def run(%{amount: amount}, %{agent_state: state}),
      do: {:ok, %{state | count: state.count + amount}}
  end

  defmodule ProjectedOutput do
    use Jido.Action,
      name: "authoring_projected_output",
      output_schema: Zoi.object(%{state: Zoi.map(), reply: Zoi.string()})

    def run(_params, _context), do: {:ok, %{state: %{}, reply: "done"}}
  end

  defmodule Flow do
    use Jido.Flow,
      name: "authoring_flow",
      schema: Zoi.object(%{amount: Zoi.integer()}),
      output_schema: Zoi.any()

    flow do
      step "add", action: Add, params: %{amount: input(:amount)}
      output result("add")
    end
  end

  defmodule CountTurns do
    use Jido.Plugin

    @impl true
    defdelegate state_spec(opts), to: JidoTest.Agent.AuthoringTest.CountTurns.Agent

    @impl true
    defdelegate reduce(reduction, opts), to: JidoTest.Agent.AuthoringTest.CountTurns.Agent
  end

  defmodule CountTurns.Agent do
    @behaviour Jido.Plugin

    def state_spec(opts),
      do: {:turns, Zoi.integer() |> Zoi.default(Keyword.get(opts, :initial, 0))}

    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
  end

  defmodule PassThrough do
    use Jido.Plugin

    @impl true
    defdelegate state_spec(opts), to: JidoTest.Agent.AuthoringTest.PassThrough.Agent

    @impl true
    defdelegate prepare(preparation, opts), to: JidoTest.Agent.AuthoringTest.PassThrough.Agent
  end

  defmodule PassThrough.Agent do
    @behaviour Jido.Plugin
    def state_spec(_opts), do: :none
    def prepare(_preparation, _opts), do: {:ok, nil}
  end

  defmodule PreparedCounter do
    use Jido.Agent, name: "prepared_counter"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/prepared"

      route "prepared.add", Add, as: :add do
        state(from: output())
      end
    end
  end

  defmodule Match do
    def positive?(%{data: %{amount: amount}}), do: is_integer(amount) and amount > 0
    def positive?(_signal), do: false
  end

  defmodule RawCounter do
    use Jido.Agent, name: "raw_counter", metadata: %{day: ~D[2026-09-03]}

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "raw.*", Add do
        state(from: output())
      end

      route "event.*", Add do
        state(from: output())
      end
    end
  end

  defmodule ListInputs do
    use Jido.Action,
      name: "list_inputs",
      schema:
        Zoi.object(%{
          items: Zoi.array(Zoi.integer()) |> Zoi.optional(),
          nullable_items: Zoi.array(Zoi.integer()) |> Zoi.nullable() |> Zoi.optional(),
          options: Zoi.keyword(value: Zoi.integer()) |> Zoi.optional(),
          empty: Zoi.literal([]) |> Zoi.optional(),
          anything: Zoi.any() |> Zoi.optional()
        }),
      output_schema: Zoi.any()

    def run(_params, %{agent_state: state}), do: {:ok, state}
  end

  defmodule NamedInputs do
    use Jido.Action,
      name: "named_inputs",
      schema:
        Zoi.object(%{
          server: Zoi.integer(),
          opts: Zoi.integer(),
          _: Zoi.integer(),
          _private: Zoi.integer(),
          "user-id": Zoi.integer(),
          amount: Zoi.integer() |> Zoi.optional(),
          amount_or_opts: Zoi.integer() |> Zoi.optional()
        }),
      output_schema: Zoi.any()

    def run(input, _context), do: {:ok, input}
  end

  defmodule NamedAgent do
    use Jido.Agent, name: "named_agent"

    routes do
      signal_source "/named"

      route "named.inputs", NamedInputs, as: :compose do
        state(from: output())
      end
    end
  end

  defmodule Counter do
    use Jido.Agent,
      name: "authoring_counter",
      description: "All authoring forms",
      vsn: 7,
      metadata: %{owner: :test, nested: {:tag, <<255>>}}

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    plugins do
      plugin CountTurns, config: %{initial: 0}
      plugin PassThrough, config: %{label: :second}
    end

    routes do
      signal_source "/authoring"

      route "authoring.add", Add, as: :add, defaults: %{amount: 1, flag: false} do
        state(from: output())
      end

      route "authoring.flow", Flow, as: :flow_add, defaults: %{amount: 2} do
        state(from: output())
      end
    end
  end

  defmodule UnexposedCounter do
    use Jido.Agent,
      name: "authoring_counter",
      description: "All authoring forms",
      vsn: 7,
      metadata: %{owner: :test, nested: {:tag, <<255>>}}

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    plugins do
      plugin CountTurns, config: %{initial: 0}
      plugin PassThrough, config: %{label: :second}
    end

    routes do
      route "authoring.add", Add, defaults: %{amount: 1, flag: false} do
        state(from: output())
      end

      route "authoring.flow", Flow, defaults: %{amount: 2} do
        state(from: output())
      end
    end
  end

  defmodule InlineCounter do
    use Jido.Agent, name: "inline_authoring_counter"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/inline-authoring"

      route "inline.add", defaults: %{multiplier: 1}, as: :add_inline do
        action %{amount: amount, multiplier: multiplier},
          name: "inline_authoring_add",
          schema:
            Zoi.object(%{
              amount: Zoi.integer(),
              multiplier: Zoi.integer() |> Zoi.default(1)
            }),
          context: context,
          output_schema: Zoi.any() do
          {:ok,
           %{context.agent_state | count: add(context.agent_state.count, amount, multiplier)}}
        end

        state(from: output())
      end
    end

    defp add(count, amount, multiplier), do: count + amount * multiplier
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I10"]
  test "the definition stores ordered routes and Plugin contributions" do
    definition = Counter.definition()
    assert definition.module == Counter
    assert definition.vsn == 7
    assert Enum.map(definition.routes, & &1.path) == ["authoring.add", "authoring.flow"]

    assert Agent.runtime_plugins(definition) == [
             {CountTurns, [initial: 0]},
             {PassThrough, [label: :second]}
           ]

    assert Enum.map(definition.extensions, & &1.provider) == [CountTurns, PassThrough]
    assert Counter.schema() == Agent.schema(definition)
    assert Counter.instantiate!(id: "defined").state == %{count: 0, turns: 0}
    refute function_exported?(UnexposedCounter, :add_signal, 1)
  end

  @tag obligation: "jido.agent.I21"
  test "generated Signal helpers have tuple and raising forms" do
    module = JidoTest.AuthoringDocsAgent
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    assert {{:function, :increment_signal, 2}, _, _, %{"en" => help}, _} =
             Enum.find(docs, fn {key, _, _, _, _} -> key == {:function, :increment_signal, 2} end)

    assert help =~ "Builds an input Signal"

    assert {{:function, :increment_signal!, 2}, _, _, %{"en" => bang_help}, _} =
             Enum.find(docs, fn {key, _, _, _, _} -> key == {:function, :increment_signal!, 2} end)

    assert bang_help =~ "raises for an invalid Signal input"
    assert {:ok, specs} = Code.Typespec.fetch_specs(module)
    assert List.keymember?(specs, {:increment_signal, 2}, 0)
    assert List.keymember?(specs, {:increment_signal!, 2}, 0)
    assert {:ok, %{data: %{}}} = module.increment_signal()
    assert %{data: %{}} = module.increment_signal!()

    assert %{data: %{amount: "not validated during construction"}} =
             module.increment_signal!(%{amount: "not validated during construction"})

    assert_raise Agent.Error, "Expected a plain Map", fn -> module.increment_signal!([]) end

    assert_raise ArgumentError, ~r/invalid input Signal/, fn ->
      module.increment_signal!(%{}, source: "not a URI reference")
    end
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I22"]
  test "Spark rejects invalid schema and identity options with a field path" do
    assert_raise Spark.Error.DslError, ~r/schema/, fn ->
      compile_agent("", "", "state do\n schema nil\n end")
    end

    for option <- ["schema: Zoi.object(%{})", "plugins: []", "routes: []"] do
      assert_raise Spark.Options.ValidationError, ~r/unknown options/, fn ->
        compile_agent("", ", #{option}")
      end
    end
  end

  @tag obligation: ["jido.agent.I4", "jido.agent.I21", "jido.agent.I22"]
  test "removed route options and invalid helpers fail at declaration" do
    for option <- ["priority: 1", "match: fn _ -> true end", "params: %{}"] do
      assert_raise CompileError, ~r/Unknown route options/, fn ->
        compile_agent("route \"test.add\", Add, #{option} do state from: output() end")
      end
    end

    for routes <- [
          "route \"test.*\", Add, as: :add do state from: output() end",
          "route \"test.add\", Add, as: :add do state from: output() end\nroute \"test.other\", Add, as: :add do state from: output() end",
          "route \"test.add\", Add do state from: output() end\nroute \"test.add\", Add do state from: output() end"
        ] do
      assert_raise Spark.Error.DslError, fn -> compile_agent(routes) end
    end

    assert_raise CompileError, ~r/unique keyword/, fn ->
      compile_agent("route \"test.add\", Add, as: :add, as: :other do state from: output() end")
    end
  end

  @tag obligation: "jido.agent.I1"
  test "a string route requires a handler and forward lowers to portable data" do
    assert_raise CompileError, ~r/requires exactly one handler/, fn ->
      compile_agent("route \"test.pass\"")
    end

    compiled =
      compile_isolated("""
      defmodule JidoTest.BareAgent#{System.unique_integer([:positive])} do
        use Jido.Agent, name: "bare"
        routes do
          route "test.pass" do
            forward to: parent()
          end
        end
      end
      """)

    {module, _} =
      Enum.find(compiled, fn {module, _} -> function_exported?(module, :definition, 0) end)

    assert [%{handler: %{kind: :forward, target: %{kind: :parent}}}] =
             module.definition().routes

    assert {:error, %{code: :unmatched_input}} = Agent.Route.select(module.definition(), "other")
  end

  @tag obligation: "jido.agent.I3"
  test "use metadata accepts mixed keys and rejects structs with a DSL error" do
    compiled = compile_agent("", ~s(, metadata: %{"owner" => "string", :owner => :atom}))

    {module, _bytecode} =
      Enum.find(compiled, fn {module, _bytecode} ->
        function_exported?(module, :definition, 0)
      end)

    assert module.definition().metadata === %{"owner" => "string", :owner => :atom}

    assert_raise Spark.Error.DslError, ~r/metadata/, fn ->
      compile_agent("", ", metadata: ~D[2026-09-13]")
    end
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I21"]
  test "inline routes compile ordinary Actions with access to private helpers" do
    target = InlineCounter.route_executable!("inline.add")

    assert {:ok, %Jido.Instruction{kind: :action, target: ^target}} =
             Jido.Instruction.resolve(target)

    assert target.name() == "inline_authoring_add"

    {:ok, signal} =
      InlineCounter.add_inline_signal(%{amount: 3, multiplier: 2})

    assert {:ok, candidate, []} =
             InlineCounter.cmd(InlineCounter.instantiate!(id: Jido.Signal.ID.generate!()), signal)

    assert candidate.state.count == 6
  end

  @tag obligation: "jido.agent.I1"
  test "inline routes accept guarded callback clauses" do
    compiled =
      compile_agent(
        """
        route "test.classify" do
          action schema: Zoi.object(%{amount: Zoi.integer()}), output_schema: Zoi.map(), context: context do
            %{amount: amount} when amount > 0 ->
              {:ok, %{context.agent_state | result: :positive}}

            _ ->
              {:ok, %{context.agent_state | result: :other}}
          end

          state from: output()
        end
        """,
        "",
        """
        state do
          schema Zoi.object(%{result: Zoi.atom() |> Zoi.default(:unset)})
        end
        """
      )

    {module, _bytecode} =
      Enum.find(compiled, fn {compiled_module, _bytecode} ->
        function_exported?(compiled_module, :instantiate!, 1)
      end)

    positive = Jido.Signal.new!("test.classify", %{amount: 1}, source: "/test")
    other = Jido.Signal.new!("test.classify", %{amount: 0}, source: "/test")

    assert {:ok, %{state: %{result: :positive}}, []} =
             module.cmd(module.instantiate!(id: Jido.Signal.ID.generate!()), positive)

    assert {:ok, %{state: %{result: :other}}, []} =
             module.cmd(module.instantiate!(id: Jido.Signal.ID.generate!()), other)
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I22"]
  test "compiled Agents canonicalize string state selectors against atom output fields" do
    compiled =
      compile_agent("""
      route "test.project", JidoTest.Agent.AuthoringTest.ProjectedOutput do
        state from: output("state")
      end
      """)

    {module, _bytecode} =
      Enum.find(compiled, fn {compiled_module, _bytecode} ->
        function_exported?(compiled_module, :definition, 0)
      end)

    assert [%{state: %{path: [:state]}}] = module.definition().routes
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I22"]
  test "compiled Agents canonicalize string reply selectors against atom output fields" do
    compiled =
      compile_agent("""
      route "test.project", JidoTest.Agent.AuthoringTest.ProjectedOutput do
        state :unchanged
        reply "test.project.done", from: output("reply")
      end
      """)

    {module, _bytecode} =
      Enum.find(compiled, fn {compiled_module, _bytecode} ->
        function_exported?(compiled_module, :definition, 0)
      end)

    assert [%{reply: %{from: %{path: [:reply]}}}] = module.definition().routes
  end

  @tag obligation: "jido.agent.I21"
  test "generated constructors preserve omitted and explicit input and fresh Signal IDs" do
    assert {:ok, %{data: %{}} = first} = Counter.add_signal(%{})
    assert {:ok, %{data: %{amount: 0}} = second} = Counter.add_signal(%{amount: 0})
    refute first.id == second.id
    assert {:ok, %{data: %{flag: false}}} = Counter.add_signal(%{flag: false})

    assert {:ok, %{id: "stable", source: "/custom"}} =
             Counter.add_signal(%{amount: 2}, source: "/custom", id: "stable")

    assert {:ok, next, []} =
             Counter.cmd(Counter.instantiate!(id: Jido.Signal.ID.generate!()), first)

    assert next.state.count == 1

    assert {:ok, signal} = Counter.add_signal(%{amount: nil})
    assert signal.data == %{amount: nil}

    assert {:error, %Jido.Action.Error.InvalidInputError{}} =
             Counter.cmd(Counter.instantiate!(id: Jido.Signal.ID.generate!()), signal)
  end

  @tag obligation: "jido.agent.I21"
  test "map inputs retain keys that overlap helper option names" do
    input = %{server: 1, opts: 2, _: 3, _private: 4, "user-id": 5, amount: 6, amount_or_opts: 7}
    assert {:ok, signal} = NamedAgent.compose_signal(input, id: "named")
    assert signal.data == input
    assert signal.id == "named"
  end

  @tag obligation: ["jido.agent.I21", "jido.agent.I22"]
  test "constructors reject non-map input and invalid envelope options" do
    for input <- [nil, [], [amount: 1], 1, ~D[2026-09-03]] do
      assert {:error, %{__exception__: true}} = Counter.add_signal(input)
    end

    for options <- [
          [input: %{}],
          [signal: []],
          [timeout: 10],
          [context: %{}],
          [type: "different"],
          [data: %{}],
          [unknown: true],
          [source: "/one", source: "/two"],
          [source: "bad source"],
          :invalid
        ] do
      assert {:error, _} = Counter.add_signal(%{}, options)
    end

    assert {:error, _} = Agent.instantiate(:missing_agent_module, [])
    assert {:error, _} = Agent.instantiate(%{}, [])
  end

  @tag obligation: "jido.agent.I20"
  test "wildcard routes work and static structs are not portable authoring values" do
    definition = RawCounter.definition()

    assert {:error, %Jido.Authoring.Error.InvalidError{code: :value}} =
             JidoTest.AgentRegistry.encode(definition, JidoTest.AgentRegistry.for(definition))

    refute function_exported?(RawCounter, :raw_signal, 1)

    agent = Agent.instantiate!(definition, id: "raw")

    for type <- ["raw.add", "event.add"] do
      signal = Jido.Signal.new!(type, %{amount: 2}, source: "/test")
      assert {:ok, candidate, []} = Agent.cmd(agent, signal)
      assert candidate.state.count == 2
    end

    signal = Jido.Signal.new!("raw.add", %{amount: -1}, source: "/test")
    assert {:ok, %{state: %{count: -1}}, []} = Agent.cmd(agent, signal)

    assert {:error, _} =
             Jido.Authoring.Registry.new(%{"runtime" => {:value, ~D[2026-09-03]}})
  end

  @tag obligation: "jido.agent.I20"
  test "Codec rejects incomplete instance shapes before it derives a definition" do
    definition = Counter.definition()

    for malformed <- [
          %{definition | id: "", state: %{}},
          %{definition | id: nil, state: %{}},
          %{definition | id: 1, state: %{}},
          %{definition | id: "instance", state: nil},
          %{definition | id: "instance", state: %URI{}},
          %{definition | id: "instance", state: []}
        ] do
      assert {:error, _error} = JidoTest.AgentRegistry.encode(malformed, %{})
    end
  end

  @tag obligation: ["jido.agent.I4", "jido.agent.I22"]
  test "malformed route collections return errors in direct forms" do
    route = {"direct.add", Add}

    for routes <- [[route | :invalid], [[route]], [[route, route]], [[]]] do
      assert {:error, _} = Agent.define(%{name: "invalid", routes: routes})
    end

    assert {:ok, built} =
             Agent.define(%{
               name: "tuple",
               routes: [
                 %{
                   path: "tuple.add",
                   handler: %{kind: :action, target: Add},
                   defaults: %{amount: 2},
                   state: %{source: :output, path: []}
                 }
               ]
             })

    assert [%{handler: %{target: Add}, defaults: %{amount: 2}}] = built.routes
  end

  @tag obligation: "jido.agent.I21"
  test "map inputs support optional list and keyword fields without ambiguity" do
    compiled =
      compile_agent("route \"test.list\", ListInputs, as: :list do state from: output() end")

    {module, _} =
      Enum.find(compiled, fn {module, _} -> function_exported?(module, :list_signal, 1) end)

    for field <- [:items, :nullable_items, :options, :empty, :anything], value <- [[], [1]] do
      input = %{field => value}
      assert {:ok, signal} = module.list_signal(input)
      assert signal.data == input
    end
  end

  @tag obligation: "jido.agent.I21"
  test "an inline route without as needs no source and generates no helper" do
    compiled =
      compile_agent(
        """
        route "test.add" do
          action params, output_schema: Zoi.map() do
            {:ok, params}
          end

          state from: output()
        end
        """,
        "",
        "",
        false
      )

    {module, _} =
      Enum.find(compiled, fn {module, _} -> function_exported?(module, :instantiate!, 1) end)

    refute function_exported?(module, :add_signal, 1)
    refute function_exported?(module, :add_signal, 2)
    signal = Jido.Signal.new!("test.add", %{}, source: "/caller")

    assert {:ok, %{state: %{}}, []} =
             module.cmd(module.instantiate!(id: Jido.Signal.ID.generate!()), signal)
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I22"]
  test "recompilation verifies the new schema of an Action defined later in the same file" do
    module = Module.concat(JidoTest, "ReloadedAgent#{System.unique_integer([:positive])}")

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      for field <- [:amount, :value] do
        compile_isolated("""
        defmodule #{inspect(module)} do
          use Jido.Agent, name: "reloaded"

          state do
            schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
          end

          routes do
            signal_source "/reloaded"
            route "reloaded.add", #{inspect(module)}.Add, as: :add do
              state from: output()
            end
          end
        end

        defmodule #{inspect(module)}.Add do
          use Jido.Action,
            name: "reloaded_add",
            schema: Zoi.object(%{#{field}: Zoi.integer()}),
            output_schema: Zoi.map()

          def run(params, _context), do: {:ok, %{count: params.#{field}}}
        end
        """)

        assert {:ok, signal} = module.add_signal(%{field => 3})

        assert {:ok, candidate, []} =
                 module.cmd(module.instantiate!(id: Jido.Signal.ID.generate!()), signal)

        assert candidate.state.count == 3
      end
    end)
  end

  @tag obligation: "jido.agent.I22"
  test "an unchanged Agent checks a reloaded Action contract" do
    module = Module.concat(JidoTest, "ActionReload#{System.unique_integer([:positive])}")
    action = Module.concat(module, Action)

    compile_isolated("""
    defmodule #{inspect(module)} do
      use Jido.Agent, name: "action_reload"
      routes do
        route "reload.run", #{inspect(action)} do
          state from: output()
        end
      end
    end
    defmodule #{inspect(action)} do
      use Jido.Action, name: "reload_action", output_schema: Zoi.map()
      def run(_params, _context), do: {:ok, %{}}
    end
    """)

    assert {:ok, _} = Jido.Agent.Validation.resolve(module)

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      compile_isolated("defmodule #{inspect(action)} do\ndef run(_, _), do: {:ok, %{}}\nend")
    end)

    assert {:error, _} = Jido.Agent.Validation.resolve(module)
    assert {:error, _} = module.instantiate(id: "invalid")
  end

  defp compile_agent(routes, opts \\ "", extra \\ "", source? \\ true) do
    name = "JidoTest.GeneratedAgent#{System.unique_integer([:positive])}"
    source = if source?, do: "signal_source \"/test\"", else: ""

    compile_isolated("""
    defmodule #{name} do
        alias JidoTest.Agent.AuthoringTest.Add, warn: false
        alias JidoTest.Agent.AuthoringTest.ListInputs, warn: false
      use Jido.Agent, name: "compiled"#{opts}
      #{extra}
      routes do
        #{source}
        #{routes}
      end
    end
    """)
  end

  defp compile_isolated(source) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        result = Code.compile_string(source, "agent_dsl_fixture.ex")
        send(parent, {self(), :compiled, result})
      end)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        receive do
          {^pid, :compiled, result} -> result
        end

      {:DOWN, ^ref, :process, ^pid, {error, stack}} ->
        reraise error, stack
    after
      10_000 -> flunk("Agent compilation did not finish")
    end
  end
end

defmodule JidoTest.Agent.AuthoringRuntimeTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias JidoTest.Agent.AuthoringTest.{Counter, InlineCounter, PreparedCounter}

  test "generated Action and Flow helpers commit the direct candidate", %{jido: jido} do
    agent = Counter.instantiate!(id: Jido.Signal.ID.generate!())
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, agent)

    {:ok, command_signal_1} = Counter.add_signal(%{amount: 3})

    assert {:ok, expected, []} =
             Counter.cmd(
               agent,
               command_signal_1
             )

    route_signal_1 = Counter.add_signal!(%{amount: 3})

    assert {:ok, ^expected, _} =
             Jido.AgentServer.call(server, route_signal_1, [])

    assert expected.state == %{count: 3, turns: 1}

    {:ok, command_signal_2} = Counter.flow_add_signal(%{amount: 2})

    assert {:ok, flow_candidate, []} =
             Counter.cmd(
               expected,
               command_signal_2
             )

    {:ok, route_signal_2} = Counter.flow_add_signal(%{amount: 2})

    assert {:ok, ^flow_candidate, _} =
             Jido.AgentServer.call(server, route_signal_2, [])

    assert flow_candidate.state == %{count: 5, turns: 2}
    assert Server.status(server).state_version == 2
  end

  test "generated inline helpers apply route defaults", %{jido: jido} do
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, InlineCounter)

    {:ok, route_signal_3} = InlineCounter.add_inline_signal(%{amount: 4})

    assert {:ok, committed, _} =
             Jido.AgentServer.call(server, route_signal_3, [])

    assert committed.state == %{count: 4}
  end

  test "a live helper forwards runtime validation without a commit", %{jido: jido} do
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, Counter)
    before = JidoTest.AgentServerAssertions.committed(server)

    {:ok, route_signal_4} = Counter.add_signal(%{amount: 2})

    assert {:error, %{__exception__: true}} =
             Jido.AgentServer.call(server, route_signal_4, timeout: :invalid)

    assert JidoTest.AgentServerAssertions.committed(server) == before

    {:ok, route_signal_5} = Counter.add_signal(%{amount: 0})

    assert {:ok, committed, _} =
             Jido.AgentServer.call(server, route_signal_5, context: %{})

    assert committed.state.count == 0
  end

  test "helpers leave executable validation to execution", %{jido: jido} do
    agent = PreparedCounter.instantiate!(id: Jido.Signal.ID.generate!())
    assert {:ok, signal} = PreparedCounter.add_signal(%{amount: 2})
    assert signal.data == %{amount: 2}
    assert {:ok, candidate, []} = PreparedCounter.cmd(agent, signal)
    assert candidate.state.count == 2

    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, agent)

    {:ok, route_signal_6} = PreparedCounter.add_signal(%{amount: 2})

    assert {:ok, ^candidate, _} =
             Jido.AgentServer.call(server, route_signal_6, [])

    assert Server.status(server).state_version == 1
  end
end
