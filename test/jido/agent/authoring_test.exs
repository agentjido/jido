defmodule JidoTest.Agent.AuthoringTest do
  use JidoTest.Case, async: false

  alias Jido.Agent
  alias Jido.Agent.{Builder, Codec}
  alias Jido.Agent.Codec.Registry
  alias Jido.AgentServer, as: Server

  defmodule Add do
    use Jido.Action,
      name: "authoring_add",
      schema: Zoi.object(%{amount: Zoi.integer(), flag: Zoi.boolean() |> Zoi.default(false)})

    def run(%{amount: amount}, %{agent_state: state}),
      do: {:ok, %{state | count: state.count + amount}}
  end

  defmodule Flow do
    use Jido.Flow, name: "authoring_flow", schema: Zoi.object(%{amount: Zoi.integer()})

    flow do
      step "add", action: Add, params: %{amount: input(:amount)}
      output result("add")
    end
  end

  defmodule CountTurns do
    use Jido.Plugin

    def state_spec(opts),
      do: {:turns, Zoi.integer() |> Zoi.default(Keyword.get(opts, :initial, 0))}

    def update_state(turns, _directives, _opts), do: {:ok, turns + 1}
  end

  defmodule PrepareAmount do
    use Jido.Plugin

    def prepare(command, _opts) do
      amount = command.signal.data.amount
      amount = if is_binary(amount), do: String.to_integer(amount), else: amount
      signal = %{command.signal | data: %{command.signal.data | amount: amount + 1}}
      {:ok, %{command | signal: signal}}
    end
  end

  defmodule PreparedCounter do
    use Jido.Agent, name: "prepared_counter"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
      plugin PrepareAmount
    end

    routes do
      signal_source "/prepared"

      route "prepared.add", Add do
        define :add, args: [:amount]
      end
    end
  end

  defmodule Match do
    def positive?(%{data: %{amount: amount}}), do: is_integer(amount) and amount > 0
    def positive?(_signal), do: false
  end

  defmodule RawCounter do
    use Jido.Agent, name: "raw_counter"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
      metadata %{day: ~D[2026-09-03]}
    end

    routes do
      route "raw.*", Add do
        match &Match.positive?/1
        priority 10
      end

      route "event.*", Add
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
        })

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
        })

    def run(input, _context), do: {:ok, input}
  end

  defmodule NamedAgent do
    use Jido.Agent, name: "named_agent"

    routes do
      signal_source "/named"

      route "named.inputs", NamedInputs do
        define :compose,
          args: [
            :server,
            :opts,
            :_,
            :_private,
            :"user-id",
            {:optional, :amount},
            {:optional, :amount_or_opts}
          ]
      end
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "authoring_counter", description: "All authoring forms"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
      metadata %{owner: :test, nested: {:tag, <<255>>}}
      plugin CountTurns, config: %{initial: 0}
    end

    routes do
      signal_source "/authoring"

      route "authoring.add", Add do
        defaults %{amount: 1}
        priority 10
        define :add, args: [{:optional, :amount}]
        define :add_exact, args: [:amount]
      end

      route "authoring.flow", Flow do
        define :flow_add, args: [:amount]
      end
    end
  end

  defmodule InlineCounter do
    use Jido.Agent, name: "inline_authoring_counter"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/inline-authoring"

      route "inline.add", defaults: %{multiplier: 1} do
        action %{amount: amount, multiplier: multiplier},
          name: "inline_authoring_add",
          schema:
            Zoi.object(%{
              amount: Zoi.integer(),
              multiplier: Zoi.integer() |> Zoi.default(1)
            }),
          context: context do
          {:ok,
           %{context.agent_state | count: add(context.agent_state.count, amount, multiplier)}}
        end

        define :add_inline, args: [:amount, {:optional, :multiplier}]
      end
    end

    defp add(count, amount, multiplier), do: count + amount * multiplier
  end

  defp builder do
    Builder.new(module: Counter, name: "authoring_counter")
    |> Builder.description("All authoring forms")
    |> Builder.schema(Counter.schema())
    |> Builder.metadata(%{owner: :test, nested: {:tag, <<255>>}})
    |> Builder.plugin(CountTurns, %{initial: 0})
    |> Builder.route("authoring.add", Add, defaults: %{amount: 1}, priority: 10)
    |> Builder.route("authoring.flow", Flow)
  end

  test "map, keyword, module, Spark, Builder and JSON forms produce equal Agents" do
    opts = [id: "parity", state: %{count: 4}]
    expected = Counter.new!(opts)
    attrs = Map.put(Counter.__agent_config__(), :module, Counter)

    assert Agent.new!(attrs) == Counter.agent()
    assert Agent.new!(Map.to_list(attrs)) == Counter.agent()
    assert Agent.instantiate!(Agent.new!(attrs), opts) == expected
    assert Agent.new!(Counter, opts) == expected
    assert Builder.build!(builder()) == Counter.agent()
    assert Builder.build!(builder(), opts) == expected
    assert Builder.build!(Builder.new(Counter), opts) == expected

    assert {:ok, document, registry} = Codec.encode(expected)
    assert Map.has_key?(hd(document["routes"]), "defaults")
    refute Map.has_key?(hd(document["routes"]), "params")
    assert {:ok, ^expected} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry, opts)
    assert {:ok, definition} = Codec.decode(document, registry)
    assert definition == Counter.agent()
    assert {:ok, ^document} = Codec.encode(definition, registry)
    refute Map.has_key?(document, "state")
    refute Map.has_key?(document, "id")

    assert {:ok, ^document} =
             Codec.encode(Counter.new!(id: "different", state: %{count: 7}), registry)

    assert Enum.map(definition.routes, & &1.path) == ["authoring.add", "authoring.flow"]
    assert definition.plugins == [{CountTurns, [initial: 0]}]
  end

  test "all forms use the same direct and live execution path", %{jido: jido} do
    {:ok, document, registry} = Codec.encode(Counter.agent())

    instances = [
      Counter.new!(id: "spark"),
      Builder.build!(builder(), id: "builder"),
      elem(Codec.decode(document, registry, id: "codec"), 1)
    ]

    for agent <- instances do
      {:ok, server} = Jido.start_agent(jido, agent)
      signal = Counter.add_signal!(3)
      assert {:ok, expected, []} = Counter.cmd(agent, signal)
      assert {:ok, ^expected} = Counter.add(server, 3)
      assert expected.state == %{count: 3, turns: 1}
      assert {:ok, flow_candidate, []} = Counter.cmd(expected, Counter.flow_add_signal!(2))
      assert {:ok, ^flow_candidate} = Counter.flow_add(server, 2)
    end
  end

  test "inline routes compile ordinary Actions that Builder and Codec can reuse", %{jido: jido} do
    target = InlineCounter.route_action("inline.add")
    assert target.__jido_executable__().kind == :action
    assert target.name() == "inline_authoring_add"

    signal = InlineCounter.add_inline_signal!(3, 2)
    assert {:ok, candidate, []} = InlineCounter.cmd(InlineCounter.new!(), signal)
    assert candidate.state.count == 6

    {:ok, server} = Jido.start_agent(jido, InlineCounter)
    assert {:ok, committed} = InlineCounter.add_inline(server, 4)
    assert committed.state.count == 4

    built =
      Builder.new(name: "inline_builder")
      |> Builder.schema(InlineCounter.schema())
      |> Builder.route("inline.add", target, defaults: %{multiplier: 1})
      |> Builder.build!()

    assert {:ok, built_candidate, []} =
             Agent.cmd(Agent.instantiate!(built), InlineCounter.add_inline_signal!(5, 3))

    assert built_candidate.state.count == 15

    assert {:ok, document, registry} = Codec.encode(InlineCounter.agent())
    assert {:ok, decoded} = Codec.decode(document, registry)
    assert hd(decoded.routes).target == {target, %{multiplier: 1}}
  end

  test "generated constructors preserve omission, explicit values and new Signal IDs" do
    assert {:ok, %{data: %{}} = first} = Counter.add_signal()
    assert {:ok, %{data: %{amount: 0}} = second} = Counter.add_signal(0)
    refute first.id == second.id
    assert Counter.add_signal!(nil).data == %{amount: nil}
    assert Counter.add_signal!(input: %{flag: false}).data == %{flag: false}
    assert Counter.add_signal!(2, signal: [source: "/custom", id: "stable"]).id == "stable"
    assert Counter.add_signal!(2, signal: [source: "/custom"]).source == "/custom"
    assert {:ok, next, []} = Counter.cmd(Counter.new!(), first)
    assert next.state.count == 1

    assert {:error, %Jido.Action.Error.InvalidInputError{}} =
             Counter.cmd(Counter.new!(), Counter.add_signal!(nil))
  end

  test "generated documentation exposes named arguments, optional forms and execution contracts" do
    module = Jido.Examples.MinimalAgent
    assert {_, ["increment(server)"], _, _} = function_docs(module, :increment, 1)

    assert {_, ["increment(server, amount_or_opts)"], _, _} =
             function_docs(module, :increment, 2)

    assert {_, ["increment(server, amount, opts)"], %{"en" => call_help}, _} =
             function_docs(module, :increment, 3)

    assert call_help =~ "{:ok, committed_agent}"
    assert call_help =~ "does not cancel a Turn"
    assert call_help =~ "`:context`"
    assert call_help =~ "without coercion or executable validation"

    assert {_, ["increment_signal()"], _, _} = function_docs(module, :increment_signal, 0)

    assert {_, ["increment_signal(amount_or_opts)"], %{"en" => optional_help}, _} =
             function_docs(module, :increment_signal, 1)

    assert optional_help =~ "either its positional input value or a keyword options list"
    assert optional_help =~ "Omitted optional inputs remain absent"

    assert {_, ["increment_signal(amount, opts)"], %{"en" => signal_help}, _} =
             function_docs(module, :increment_signal, 2)

    assert signal_help =~ "{:ok, signal}"
    assert signal_help =~ "accepted only by the live call helper"

    assert {_, ["increment_signal!(amount, opts)"], %{"en" => bang_help}, _} =
             function_docs(module, :increment_signal!, 2)

    assert bang_help =~ "Returns the Signal or raises"

    assert {_, ["set_count(server, count, opts)"], _, _} =
             function_docs(Jido.Examples.TypedCommandAgent, :set_count, 3)
  end

  test "generated specs keep raw input broad and describe the actual return values" do
    module = Jido.Examples.MinimalAgent

    assert function_spec(module, :increment_signal, 2) ==
             normalized_spec(
               "increment_signal(term(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}"
             )

    assert function_spec(module, :increment_signal!, 2) ==
             normalized_spec("increment_signal!(term(), keyword()) :: Jido.Signal.t()")

    assert function_spec(module, :increment, 3) ==
             normalized_spec(
               "increment(Jido.AgentServer.server(), term(), keyword()) :: {:ok, Jido.Agent.t()} | {:error, term()}"
             )
  end

  test "named arguments preserve payloads when fields overlap helper names or need escaping" do
    assert {:ok, signal} = NamedAgent.compose_signal(1, 2, 3, 4, 5, 6, 7, signal: [id: "named"])

    assert signal.data == %{
             server: 1,
             opts: 2,
             _: 3,
             _private: 4,
             "user-id": 5,
             amount: 6,
             amount_or_opts: 7
           }

    assert NamedAgent.compose_signal!(1, 2, 3, 4, 5, input: %{amount: 6}).data == %{
             server: 1,
             opts: 2,
             _: 3,
             _private: 4,
             "user-id": 5,
             amount: 6
           }
  end

  test "interface packaging and envelope options reject ambiguity" do
    for arguments <- [
          [1, [input: %{amount: 2}]],
          [1, [input: []]],
          [1, [timeout: 10]],
          [1, [signal: [type: "different"]]],
          [1, [signal: [data: %{}]]],
          [1, [unknown: true]],
          [1, [input: %{}, input: %{}]]
        ] do
      assert {:error, _} = apply(Counter, :add_signal, arguments)
    end

    assert_raise Jido.Error.ValidationError, fn -> Counter.add_signal!(1, input: %{amount: 2}) end
    assert {:error, _} = Counter.add_signal(1, signal: [source: "bad source"])
    assert {:error, _} = Agent.new(:missing_agent_module, [])
    assert {:error, _} = Agent.new(%{}, [])
  end

  test "a live helper forwards runtime validation without a commit", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Counter)
    before = Server.snapshot(server)
    assert {:error, %Jido.Error.ValidationError{}} = Counter.add(server, 2, timeout: :invalid)
    assert Server.snapshot(server) == before
    assert {:ok, committed} = Counter.add(server, 0, context: %{})
    assert committed.state.count == 0
  end

  test "helpers leave Plugin preparation and executable validation to execution", %{jido: jido} do
    agent = PreparedCounter.new!()
    assert {:ok, signal} = PreparedCounter.add_signal("2")
    assert signal.data == %{amount: "2"}
    assert {:ok, candidate, []} = PreparedCounter.cmd(agent, signal)
    assert candidate.state.count == 3

    {:ok, server} = Jido.start_agent(jido, agent)
    assert {:ok, ^candidate} = PreparedCounter.add(server, "2")
    assert Server.snapshot(server).state_version == 1
  end

  test "raw wildcard and predicate routes and static structs survive the Codec" do
    definition = RawCounter.agent()
    assert {:ok, document, registry} = Codec.encode(definition)
    assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    assert {:ok, rebuilt} = Builder.build(Builder.new(RawCounter))
    assert rebuilt == definition
    refute function_exported?(RawCounter, :raw_signal, 1)

    agent = Agent.instantiate!(rebuilt, id: "raw")

    for type <- ["raw.add", "event.add"] do
      signal = Jido.Signal.new!(type, %{amount: 2}, source: "/test")
      assert {:ok, candidate, []} = Agent.cmd(agent, signal)
      assert candidate.state.count == 2
    end

    signal = Jido.Signal.new!("raw.add", %{amount: -1}, source: "/test")
    assert {:error, %Jido.Error.RoutingError{}} = Agent.cmd(agent, signal)
    assert {:error, _} = Registry.new(%{"runtime" => {:value, %{~D[2026-09-03] | day: self()}}})
  end

  test "Builder keeps its first error and never creates a half instance" do
    failed = Builder.new(name: "valid") |> Builder.route("invalid..path", Add)
    assert {:error, error} = Builder.build(failed)

    assert {:error, ^error} =
             failed |> Builder.plugin(:missing_plugin) |> Builder.name("other") |> Builder.build()

    assert {:error, _} = Builder.build(Builder.new(state: %{count: 1}))
    assert {:error, _} = Builder.build(Builder.new([:invalid]))
    assert {:error, _} = Builder.build(Builder.new(:missing_agent_module))
    assert {:error, _} = Builder.build(builder(), name: "override")
    assert_raise Jido.Error.ValidationError, fn -> Builder.build!(Builder.new(unknown: true)) end
  end

  test "Plugin Codec uses the same record and Registry as Agent Codec" do
    {:ok, document, registry} = Codec.encode(Counter.agent())
    [plugin] = Counter.agent().plugins
    assert {:ok, encoded} = Jido.Plugin.Codec.encode(plugin, registry)
    assert document["plugins"] == [encoded]

    assert {:ok, ^plugin} =
             Jido.Plugin.Codec.decode(JSON.decode!(JSON.encode!(encoded)), registry)

    assert {:ok, encoded, registry} = Jido.Plugin.Codec.encode(plugin)
    assert {:ok, ^plugin} = Jido.Plugin.Codec.decode(encoded, registry)
    assert {:error, _} = Jido.Plugin.Codec.decode(Map.put(encoded, "state", %{}), registry)
  end

  test "trusted aliases decode and re-encode with the canonical identifier" do
    {:ok, document, registry} = Codec.encode(Counter.agent())
    canonical = document["module"]
    registry = Registry.new!(Map.put(registry.entries, "old/counter", {:alias, canonical}))
    assert {:ok, definition} = Codec.decode(%{document | "module" => "old/counter"}, registry)
    assert {:ok, ^document} = Codec.encode(definition, registry)
    assert {:error, _} = Registry.new(%{"one" => {:alias, "two"}, "two" => {:alias, "one"}})
    assert {:error, _} = Registry.new(%{"one" => {:atom, :x}, "two" => {:atom, :x}})
    assert {:error, _} = Registry.new(%{"bad" => {:route_match, fn _ -> true end}})
  end

  test "Codec rejects malformed documents without deriving atoms or modules" do
    {:ok, document, registry} = Codec.encode(Counter.agent())

    for bad <- [
          nil,
          [],
          Map.put(document, "unexpected", true),
          Map.delete(document, "schema"),
          %{document | "version" => 99},
          %{document | "module" => "Elixir.DoesNotExist"},
          %{document | "schema" => document["module"]},
          %{document | "plugins" => %{}},
          %{document | "metadata" => %{"$type" => "atom", "id" => "never/registered"}},
          %{
            document
            | "metadata" => %{"$type" => "map", "entries" => [["same", 1], ["same", 2]]}
          },
          %{document | "routes" => [Map.put(hd(document["routes"]), "kind", "function")]},
          %{document | "metadata" => self()},
          %{document | "metadata" => [1 | 2]}
        ] do
      assert {:error, _} = Codec.decode(bad, registry)
    end

    assert {:error, _} = Codec.decode(document, %{})
    assert {:error, _} = Codec.decode(document, registry, state: %{count: "bad"})
  end

  test "Codec bounds documents and rejects runtime data on encode" do
    {:ok, document, registry} = Codec.encode(Counter.agent())
    deep = Enum.reduce(1..102, nil, fn _, acc -> [acc] end)

    for value <- [deep, List.duplicate(0, 10_001), String.duplicate("a", 1_048_577), <<255>>] do
      assert {:error, _} = Codec.decode(%{document | "metadata" => value}, registry)
    end

    for value <- [self(), make_ref(), fn -> :ok end, [1 | 2]] do
      assert {:error, _} = Codec.encode(%{Counter.agent() | metadata: %{runtime: value}})
    end
  end

  test "direct construction accepts the same route option form" do
    assert {:ok, agent} =
             Agent.new(
               name: "direct",
               routes: [{"direct.add", Add, defaults: %{amount: 2}, priority: 20}]
             )

    assert [%{priority: 20, target: {Add, %{amount: 2}}}] = agent.routes

    assert {:ok, ^agent} =
             Agent.new(
               name: "direct",
               routes: [%{path: "direct.add", target: Add, defaults: %{amount: 2}, priority: 20}]
             )

    assert {:error, _} = Agent.new(name: "old", routes: [{"old.add", Add, params: %{amount: 2}}])

    assert {:error, _} =
             Builder.new(name: "old")
             |> Builder.route("old.add", Add, params: %{amount: 2})
             |> Builder.build()

    options = [label: "ordered", initial: 0]
    expected = Agent.new!(name: "ordered", plugins: [{CountTurns, options}])

    assert Builder.new(name: "ordered")
           |> Builder.plugin(CountTurns, options)
           |> Builder.build!() == expected
  end

  test "malformed route collections return errors in direct and Builder forms" do
    route = {"direct.add", Add}

    for routes <- [[route | :invalid], [[route]], [[route, route]], [[]]] do
      assert {:error, _} = Agent.new(name: "invalid", routes: routes)
      assert {:error, _} = Builder.build(Builder.new(name: "invalid", routes: routes))
    end

    assert {:error, _} = Builder.build(Builder.new(name: "invalid", plugins: [CountTurns | 1]))

    assert {:ok, built} =
             Builder.new(name: "tuple")
             |> Builder.route("tuple.add", {Add, %{amount: 2}})
             |> Builder.build()

    assert [%{target: {Add, %{amount: 2}}}] = built.routes
  end

  test "optional list inputs cannot be mistaken for interface options" do
    for field <- [:items, :nullable_items, :options, :empty, :anything] do
      assert_raise CompileError, ~r/must use input options/, fn ->
        compile_agent("""
        route "test.list", ListInputs do
          define :list, args: [{:optional, #{inspect(field)}}]
        end
        """)
      end
    end
  end

  test "compile diagnostics reject invalid interface declarations" do
    cases = [
      {"route \"test.*\", Add do\n define :add, args: [:amount]\nend", "exact route"},
      {"route \"test.add\", Add do\n define :add, args: [:missing]\nend", "Unknown executable"},
      {"route \"test.add\", Add do\n define :add, args: [:amount, :amount]\nend",
       "Duplicate interface argument"},
      {"route \"test.add\", Add do\n define :add, args: [{:optional, :amount}, :flag]\nend",
       "optional arguments last"},
      {"route \"test.add\", Add do\n define :new\nend", "Generated function conflicts"},
      {"route \"test.add\", Add do\n define :add\n define :add\nend", "Duplicate interface name"},
      {"route \"test.add\", Add do\n define :add\nend\nroute \"test.add\", Add",
       "exactly one route"}
    ]

    for {routes, message} <- cases do
      assert_raise CompileError, ~r/#{message}/, fn -> compile_agent(routes) end
    end
  end

  test "inline route diagnostics reject missing, mixed, duplicate, and bound declarations" do
    assert_raise CompileError, ~r/requires a target module or one inline Action/, fn ->
      compile_agent("route \"test.add\" do\n define :add\nend")
    end

    assert_raise CompileError, ~r/cannot combine a target module with an inline Action/, fn ->
      compile_agent("""
      route "test.add", Add do
        action params do
          {:ok, params}
        end
      end
      """)
    end

    assert_raise CompileError, ~r/only one inline Action/, fn ->
      compile_agent("""
      route "test.add" do
        action params do
          {:ok, params}
        end
        action other do
          {:ok, other}
        end
      end
      """)
    end

    assert_raise CompileError, ~r/inline Action callback requires/, fn ->
      compile_agent("""
      route "test.add" do
        action value <- 1 do
          {:ok, %{count: value}}
        end
      end
      """)
    end
  end

  test "compile diagnostics reject mixed fields, missing source and manual collisions" do
    assert_raise CompileError, ~r/both keyword and block/, fn ->
      compile_agent("route \"test.add\", Add", ", routes: []")
    end

    assert_raise CompileError, ~r/signal_source is required/, fn ->
      compile_agent("route \"test.add\", Add do\n define :add\nend", "", "", false)
    end

    assert_raise CompileError, ~r/Generated function conflicts/, fn ->
      compile_agent(
        "route \"test.add\", Add do\n define :add\nend",
        "",
        "def add_signal(), do: :manual"
      )
    end
  end

  test "removed route params and Plugin labels fail compilation" do
    assert_raise Spark.Error.DslError, ~r/params/, fn ->
      compile_agent("route \"test.add\", Add, params: %{amount: 1}")
    end

    assert_raise Spark.Error.DslError, ~r/as/, fn ->
      compile_agent("", "", """
      agent do
        plugin JidoTest.Agent.AuthoringTest.CountTurns, as: :counter
      end
      """)
    end
  end

  test "recompilation verifies the new schema of an Action defined later in the same file" do
    module = Module.concat(JidoTest, "ReloadedAgent#{System.unique_integer([:positive])}")

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      for field <- [:amount, :value] do
        compile_isolated("""
        defmodule #{inspect(module)} do
          use Jido.Agent, name: "reloaded"

          agent do
            schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
          end

          routes do
            signal_source "/reloaded"
            route "reloaded.add", #{inspect(module)}.Add do
              define :add, args: [#{inspect(field)}]
            end
          end
        end

        defmodule #{inspect(module)}.Add do
          use Jido.Action,
            name: "reloaded_add",
            schema: Zoi.object(%{#{field}: Zoi.integer()})

          def run(params, _context), do: {:ok, %{count: params.#{field}}}
        end
        """)

        assert {:ok, candidate, []} = module.cmd(module.new!(), module.add_signal!(3))
        assert candidate.state.count == 3
      end
    end)
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

  defp function_docs(module, name, arity) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    {{:function, ^name, ^arity}, anno, signatures, doc, metadata} =
      Enum.find(docs, fn {key, _, _, _, _} -> key == {:function, name, arity} end)

    {anno, signatures, doc, metadata}
  end

  defp function_spec(module, name, arity) do
    {:ok, specs} = Code.Typespec.fetch_specs(module)
    {{^name, ^arity}, [spec]} = List.keyfind(specs, {name, arity}, 0)

    name
    |> Code.Typespec.spec_to_quoted(spec)
    |> Macro.to_string()
    |> normalized_spec()
  end

  defp normalized_spec(source), do: String.replace(source, ~r/\s+/, "")
end
